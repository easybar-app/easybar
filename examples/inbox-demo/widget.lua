-- Publishes representative test data for the native inbox.

local SOURCE = "Inbox demo"
local DEMO_DELAY_SECONDS = 1.25
local DEMO_ORDER = 10000

---@type EasyBarInboxSourcePresentation
local GITHUB = {
	name = "GitHub",
	icon = easybar.asset("./assets/github.svg"),
	color = "#A371F7",
	order = DEMO_ORDER,
}
---@type EasyBarInboxSourcePresentation
local GITLAB = {
	name = "GitLab",
	icon = easybar.asset("./assets/gitlab.svg"),
	color = "#FC6D26",
	order = DEMO_ORDER,
}
---@type EasyBarInboxSourcePresentation
local HOMEBREW = {
	name = "Homebrew",
	icon = easybar.asset("./assets/brew.svg"),
	color = "#FBB040",
	order = DEMO_ORDER,
}

--- Builds fresh demo items with timestamps relative to the current refresh.
---@return EasyBarInboxItem[] items
local function make_demo_items()
	local now = os.time()

	return {
		{
			id = "github-review",
			title = "Review requested on pull request #482",
			body = "The macOS checks passed and the change is ready for review.",
			timestamp = now,
			category = "Pull requests",
			severity = "success",
			unread = true,
			source = GITHUB,
		},
		{
			id = "github-security",
			title = "Dependabot found a critical vulnerability",
			body = "`swift-nio` should be upgraded before the next release.",
			format = "markdown",
			timestamp = now - 90,
			category = "Security",
			severity = "error",
			unread = true,
			source = GITHUB,
		},
		{
			id = "github-mention",
			title = "You were mentioned in issue #917",
			body = "A question is waiting for your input.",
			timestamp = now - 180,
			category = "Issues",
			severity = "info",
			unread = false,
			source = GITHUB,
		},
		{
			id = "gitlab-pipeline",
			title = "Pipeline requires attention",
			body = "The deploy job is waiting for manual approval.",
			timestamp = now - 270,
			category = "Pipelines",
			severity = "warning",
			unread = true,
			source = GITLAB,
		},
		{
			id = "gitlab-merge-request",
			title = "Merge request !128 is ready",
			body = "All discussions are resolved and the pipeline passed.",
			timestamp = now - 360,
			category = "Merge requests",
			severity = "success",
			unread = true,
			source = GITLAB,
		},
		{
			id = "gitlab-issue",
			title = "Issue #73 was assigned to you",
			body = "Investigate the intermittent authentication timeout.",
			timestamp = now - 450,
			category = "Issues",
			severity = "info",
			unread = false,
			source = GITLAB,
		},
		{
			id = "brew-outdated",
			title = "Three packages can be upgraded",
			body = "formulae: lua, swiftformat · casks: visual-studio-code",
			timestamp = now - 540,
			category = "Packages",
			severity = "info",
			unread = false,
			source = HOMEBREW,
		},
		{
			id = "brew-manual-cask",
			title = "docker-desktop",
			body = "4.50.0 → 4.51.0 · manual update required · Update through Docker Desktop.",
			timestamp = now - 630,
			category = "Casks",
			severity = "warning",
			unread = true,
			source = HOMEBREW,
		},
		{
			id = "brew-pinned",
			title = "Pinned formula was not upgraded",
			body = "postgresql@16 remains on 16.3.",
			timestamp = now - 720,
			category = "Formulae",
			severity = "warning",
			unread = true,
			source = HOMEBREW,
		},
		{
			id = "brew-error",
			title = "Could not refresh package metadata",
			body = "Homebrew could not reach the package registry.",
			timestamp = now - 810,
			category = "Updates",
			severity = "error",
			unread = true,
			source = HOMEBREW,
		},
	}
end

local source_busy = false

--- Publishes the source context actions for the current busy state.
local function configure_source_actions()
	local actions
	if source_busy then
		actions = {
			{ id = "activity", title = "Refreshing demo…", enabled = false, busy = true },
		}
	else
		actions = {
			{ id = "refresh", title = "Add demo" },
			{ id = "clear", title = "Clear demo" },
		}
	end
	easybar.inbox.configure(SOURCE, { order = DEMO_ORDER, actions = actions })
end

configure_source_actions()

easybar.inbox.on_context_action(SOURCE, function(event)
	if event.action_id == "refresh" and not source_busy then
		source_busy = true
		configure_source_actions()
		easybar.after(DEMO_DELAY_SECONDS, function()
			source_busy = false
			configure_source_actions()
			easybar.inbox.replace(SOURCE, make_demo_items())
		end)
	elseif event.action_id == "clear" then
		easybar.inbox.clear(SOURCE)
	end
end)

-- Loading the widget registers its actions but leaves item creation to Refresh.
easybar.inbox.clear(SOURCE)
