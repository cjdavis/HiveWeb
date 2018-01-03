function display_storage_data(data, $curse_panel)
	{
	var i, dt, html = "<a href=\"" + panel_urls.storage_request + "\">Request a new spot</a><br /><br />";

	if (!data.slots.length)
		html += "You have no storage slots assigned.";

	if (data.requests.length)
		{
		html += "<h5>Requests</h5><ul>";
		for (i = 0; i < data.requests.length; i++)
			{
			dt = new Date(data.requests[i].created_at);
			html += "<li>Submitted on "
				+ dt.toLocaleDateString() + " " + dt.toLocaleTimeString() + "</li>";
			}
		html += "</ul>";
		}

	$curse_panel.find(".panel-body").html(html);
	}

function display_curse_data(data, $curse_panel)
	{
	var curse, i, html = "<ol class=\"curses\">", date;

	if (!("curses" in data) || !data.curses.length)
		{
		$curse_panel.find(".panel-body").html("You have no notifications!");
		return;
		}

	for (i = 0; i < data.curses.length; i++)
		{
		curse = data.curses[i];
		date   = new Date(curse.issued_at);

		html += "<li title=\"Issued " + date.toLocaleDateString() + " " + date.toLocaleTimeString() + " by "
			+ curse.issuing_member.fname + " " + curse.issuing_member.lname + "\">";
		html += "<h5>" + curse.curse.display_name + "</h5>" + curse.curse.notification + "</li>";
		}
	
	html += "</ol>";
	$curse_panel.find(".panel-body").html(html);
	}

$(function() { init_panel("curse", display_curse_data); });
$(function() { init_panel("storage", display_storage_data, false); });
