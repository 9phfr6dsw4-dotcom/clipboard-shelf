-- Finds the launched app's status item by process ID and exact accessibility description,
-- then clicks it or prints its frame as "x|y|width|height". Nothing is matched by process
-- name, and no accessibility error is swallowed: any failed query fails the whole call.
-- NSPopover windows are not exposed to System Events (verified on the GitHub macOS 15 and
-- 26 runners), so popover geometry comes from the PID's CGWindowList inventory instead.
-- Usage: osascript readme-media-status-item.applescript click|frame PID DESCRIPTION
on run argv
	if (count of argv) is not 3 then error "usage: click|frame PID DESCRIPTION" number 1000
	set mode to item 1 of argv
	if mode is not "click" and mode is not "frame" then error "unknown_mode" number 1004
	set appPid to (item 2 of argv) as integer
	set expectedDescription to item 3 of argv
	tell application "System Events"
		set matchingProcesses to every process whose unix id is appPid
		if (count of matchingProcesses) is not 1 then error "launched_process_unavailable" number 1001
		tell item 1 of matchingProcesses
			set barCount to count of menu bars
			if barCount is 0 then error "status_menu_bar_unavailable" number 1002
			set statusMatches to {}
			repeat with barIndex from 1 to barCount
				repeat with candidate in (every menu bar item of menu bar barIndex)
					set itemDescription to description of candidate
					if itemDescription is not missing value and (itemDescription as text) is expectedDescription then set end of statusMatches to contents of candidate
				end repeat
			end repeat
			if (count of statusMatches) is not 1 then error "status_item_not_unique:" & (count of statusMatches) number 1003
			set statusItem to item 1 of statusMatches
			if mode is "click" then
				click statusItem
				return "clicked"
			end if
			set statusPosition to position of statusItem
			set statusSize to size of statusItem
			return ((item 1 of statusPosition as integer) as text) & "|" & ((item 2 of statusPosition as integer) as text) & "|" & ((item 1 of statusSize as integer) as text) & "|" & ((item 2 of statusSize as integer) as text)
		end tell
	end tell
end run
