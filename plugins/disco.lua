-- Verse XMPP Library
-- Copyright (C) 2010 Hubert Chathi <hubert@uhoreg.ca>
-- Copyright (C) 2010 Matthew Wild <mwild1@gmail.com>
--
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local verse = require "verse";
local b64 = require("mime").b64;
local sha1 = require("util.hashes").sha1;
local calculate_hash = require "util.caps".calculate_hash;

local xmlns_caps = "http://jabber.org/protocol/caps";
local xmlns_disco = "http://jabber.org/protocol/disco";
local xmlns_disco_info = xmlns_disco.."#info";
local xmlns_disco_items = xmlns_disco.."#items";

function verse.plugins.disco(stream)
	stream:add_plugin("presence");
	local disco_info_mt = {
		__index = function(t, k)
			local node = { identities = {}, features = {} };
			if k == "identities" or k == "features" then
				return t[false][k]
			end
			t[k] = node;
			return node;
		end,
	};
	local disco_items_mt = {
		__index = function(t, k)
			local node = { };
			t[k] = node;
			return node;
		end,
	};
	stream.disco = {
		cache = {},
		info = setmetatable({
			[false] = {
				identities = {
					{category = 'client', type='pc', name='Verse'},
				},
				features = {
					[xmlns_caps] = true,
					[xmlns_disco_info] = true,
					[xmlns_disco_items] = true,
				},
			},
		}, disco_info_mt);
		items = setmetatable({[false]={}}, disco_items_mt);
	};

	stream.caps = {}
	stream.caps.node = 'http://code.matthewwild.co.uk/verse/'

	local function build_self_disco_info_stanza(query_node)
		local node = stream.disco.info[query_node or false];
		if query_node and query_node == stream.caps.node .. "#" .. stream.caps.hash then
			node = stream.disco.info[false];
		end
		local identities, features = node.identities, node.features

		-- construct the response
		local result = verse.stanza("query", {
			xmlns = xmlns_disco_info,
			node = query_node,
		});
		for _,identity in pairs(identities) do
			result:tag('identity', identity):up()
		end
		for feature in pairs(features) do
			result:tag('feature', { var = feature }):up()
		end
		return result;
	end

	setmetatable(stream.caps, {
		__call = function (...) -- vararg: allow calling as function or member
			-- retrieve the c stanza to insert into the
			-- presence stanza
			local hash = calculate_hash(build_self_disco_info_stanza())
			stream.caps.hash = hash;
			-- TODO proper caching.... some day
			return verse.stanza('c', {
				xmlns = xmlns_caps,
				hash = 'sha-1',
				node = stream.caps.node,
				ver = hash
			})
		end
	})

	function stream:set_identity(identity, node)
		self.disco.info[node or false].identities = { identity };
		stream:resend_presence();
	end

	function stream:add_identity(identity, node)
		local identities = self.disco.info[node or false].identities;
		identities[#identities + 1] = identity;
		stream:resend_presence();
	end

	function stream:add_disco_feature(feature, node)
		local feature = feature.var or feature;
		self.disco.info[node or false].features[feature] = true;
		stream:resend_presence();
	end

	function stream:remove_disco_feature(feature, node)
		local feature = feature.var or feature;
		self.disco.info[node or false].features[feature] = nil;
		stream:resend_presence();
	end

	function stream:add_disco_item(item, node)
		local items = self.disco.items[node or false];
		items[#items +1] = item;
	end

	function stream:remove_disco_item(item, node)
		local items = self.disco.items[node or false];
		for i=#items,1,-1 do
			if items[i] == item then
				table.remove(items, i);
			end
		end
	end

	-- TODO Node?
	function stream:jid_has_identity(jid, category, type)
		local cached_disco = self.disco.cache[jid];
		if not cached_disco then
			return nil, "no-cache";
		end
		local identities = self.disco.cache[jid].identities;
		if type then
			return identities[category.."/"..type] or false;
		end
		-- Check whether we have any identities with this category instead
		for identity in pairs(identities) do
			if identity:match("^(.*)/") == category then
				return true;
			end
		end
	end

	function stream:jid_supports(jid, feature)
		local cached_disco = self.disco.cache[jid];
		if not cached_disco or not cached_disco.features then
			return nil, "no-cache";
		end
		return cached_disco.features[feature] or false;
	end

	function stream:get_local_services(category, type)
		local host_disco = self.disco.cache[self.host];
		if not(host_disco) or not(host_disco.items) then
			return nil, "no-cache";
		end

		local results = {};
		for _, service in ipairs(host_disco.items) do
			if self:jid_has_identity(service.jid, category, type) then
				table.insert(results, service.jid);
			end
		end
		return results;
	end

	function stream:disco_local_services(callback)
		self:disco_items(self.host, nil, function (items)
			if not items then
				return callback({});
			end
			local n_items = 0;
			local function item_callback()
				n_items = n_items - 1;
				if n_items == 0 then
					return callback(items);
				end
			end

			for _, item in ipairs(items) do
				if item.jid then
					n_items = n_items + 1;
					self:disco_info(item.jid, nil, item_callback);
				end
			end
			if n_items == 0 then
				return callback(items);
			end
		end);
	end

	function stream:disco_info(jid, node, callback)
		local disco_request = verse.iq({ to = jid, type = "get" })
			:tag("query", { xmlns = xmlns_disco_info, node = node });
		self:send_iq(disco_request, function (result)
			if result.attr.type == "error" then
				return callback(nil, result:get_error());
			end

			local identities, features = {}, {};

			for tag in result:get_child("query", xmlns_disco_info):childtags() do
				if tag.name == "identity" then
					identities[tag.attr.category.."/"..tag.attr.type] = tag.attr.name or true;
				elseif tag.name == "feature" then
					features[tag.attr.var] = true;
				end
			end


			if not self.disco.cache[jid] then
				self.disco.cache[jid] = { nodes = {} };
			end

			if node then
				if not self.disco.cache[jid].nodes[node] then
					self.disco.cache[jid].nodes[node] = { nodes = {} };
				end
				self.disco.cache[jid].nodes[node].identities = identities;
				self.disco.cache[jid].nodes[node].features = features;
			else
				self.disco.cache[jid].identities = identities;
				self.disco.cache[jid].features = features;
			end
			return callback(self.disco.cache[jid]);
		end);
	end

	function stream:disco_items(jid, node, callback)
		local disco_request = verse.iq({ to = jid, type = "get" })
			:tag("query", { xmlns = xmlns_disco_items, node = node });
		self:send_iq(disco_request, function (result)
			if result.attr.type == "error" then
				return callback(nil, result:get_error());
			end
			local disco_items = { };
			for tag in result:get_child("query", xmlns_disco_items):childtags() do
				if tag.name == "item" then
					table.insert(disco_items, {
						name = tag.attr.name;
						jid = tag.attr.jid;
						node = tag.attr.node;
					});
				end
			end

			if not self.disco.cache[jid] then
				self.disco.cache[jid] = { nodes = {} };
			end

			if node then
				if not self.disco.cache[jid].nodes[node] then
					self.disco.cache[jid].nodes[node] = { nodes = {} };
				end
				self.disco.cache[jid].nodes[node].items = disco_items;
			else
				self.disco.cache[jid].items = disco_items;
			end
			return callback(disco_items);
		end);
	end

	stream:hook("iq/"..xmlns_disco_info, function (stanza)
		local query = stanza.tags[1];
		if stanza.attr.type == 'get' and query.name == "query" then
			local query_tag = build_self_disco_info_stanza(query.attr.node);
			local result = verse.reply(stanza):add_child(query_tag);
			stream:send(result);
			return true
		end
	end);

	stream:hook("iq/"..xmlns_disco_items, function (stanza)
		local query = stanza.tags[1];
		if stanza.attr.type == 'get' and query.name == "query" then
			-- figure out what items to send
			local items = stream.disco.items[query.attr.node or false];

			-- construct the response
			local result = verse.reply(stanza):tag('query',{
				xmlns = xmlns_disco_items,
				node = query.attr.node
			})
			for i=1,#items do
				result:tag('item', items[i]):up()
			end
			stream:send(result);
			return true
		end
	end);

	local initial_disco_started;
	stream:hook("ready", function ()
		if initial_disco_started then return; end
		initial_disco_started = true;

		-- Using the disco cache, fires events for each identity of a given JID
		local function scan_identities_for_service(service_jid)
			local service_disco_info = stream.disco.cache[service_jid];
			if service_disco_info then
				for identity in pairs(service_disco_info.identities) do
					local category, type = identity:match("^(.*)/(.*)$");
					print(service_jid, category, type)
					stream:event("disco/service-discovered/"..category, {
						type = type, jid = service_jid;
					});
				end
			end
		end

		stream:disco_info(stream.host, nil, function ()
			scan_identities_for_service(stream.host);
		end);

		stream:disco_local_services(function (services)
			for _, service in ipairs(services) do
				scan_identities_for_service(service.jid);
			end
			stream:event("ready");
		end);
		return true;
	end, 50);

	stream:hook("presence-out", function (presence)
		if not presence:get_child("c", xmlns_caps) then
			presence:reset():add_child(stream:caps()):reset();
		end
	end, 10);
end

-- end of disco.lua
