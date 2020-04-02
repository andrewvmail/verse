local verse = require "verse";

local xmlns_browsing = "urn:xmpp:browsing:0";

function verse.plugins.browsing(stream)
	stream:add_plugin("pep");
	function stream:browsing(infos, callback)
		if type(infos) == "string" then
			infos = { uri = infos; };
		end

		local link = verse.stanza("page", {xmlns=xmlns_browsing})
		for info, value in pairs(infos) do
			link:tag(info):text(value):up();
		end
		return stream:publish_pep(link, callback);
	end

	stream:hook_pep(xmlns_browsing, function(event)
		local item = event.item;
		return stream:event("browsing", {
			from = event.from;
			description = item:get_child_text"description";
			keywords = item:get_child_text"keywords";
			title = item:get_child_text"title";
			uri = item:get_child_text"uri";
		});
	end);
end

