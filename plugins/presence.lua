local verse = require "verse";

function verse.plugins.presence(stream)
	stream.last_presence = nil;

	stream:hook("presence-out", function (presence)
		if not presence.attr.to then
			stream.last_presence = presence; -- Cache non-directed presence
		end
	end, 1);

	function stream:resend_presence()
		if self.last_presence then
			stream:send(self.last_presence);
		end
	end

	function stream:set_status(opts)
		local p = verse.presence();
		if type(opts) == "table" then
			if opts.show then
				p:tag("show"):text(opts.show):up();
			end
			if opts.priority or opts.prio then
				p:tag("priority"):text(tostring(opts.priority or opts.prio)):up();
			end
			if opts.status or opts.msg then
				p:tag("status"):text(opts.status or opts.msg):up();
			end
		elseif type(opts) == "string" then
			p:tag("status"):text(opts):up();
		end

		stream:send(p);
	end
end
