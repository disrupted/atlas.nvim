local M = {}

local cli = require("atlas.providers.github.client")
local normalizer = require("atlas.issues.providers.github.api.mapper")
local json = require("atlas.core.json")

local TIMELINE_QUERY = [[
query($owner:String!,$name:String!,$number:Int!,$endCursor:String){
  repository(owner:$owner,name:$name){
    issue(number:$number){
      id url body createdAt author{...actor}
      reactionGroups{content viewerHasReacted reactors(first:10){totalCount nodes{...on User{login name} ...on Bot{login}}}}
      timelineItems(first:100,after:$endCursor){
        pageInfo{hasNextPage endCursor}
        nodes{
          __typename
          ...on IssueComment{
            id url body createdAt author{...actor}
            reactionGroups{content viewerHasReacted reactors(first:10){totalCount nodes{...on User{login name} ...on Bot{login}}}}
          }
          ...on AssignedEvent{createdAt actor{...actor} assignee{...actor}}
          ...on ClosedEvent{createdAt actor{...actor} closer{...on Commit{oid}}}
          ...on ConnectedEvent{createdAt actor{...actor}}
          ...on CrossReferencedEvent{createdAt actor{...actor} source{...on Issue{title url} ...on PullRequest{title url}}}
          ...on DemilestonedEvent{createdAt actor{...actor} milestoneTitle}
          ...on DisconnectedEvent{createdAt actor{...actor}}
          ...on IssueTypeAddedEvent{createdAt actor{...actor}}
          ...on IssueTypeChangedEvent{createdAt actor{...actor}}
          ...on IssueTypeRemovedEvent{createdAt actor{...actor}}
          ...on LabeledEvent{createdAt actor{...actor} label{name}}
          ...on LockedEvent{createdAt actor{...actor}}
          ...on MarkedAsDuplicateEvent{createdAt actor{...actor}}
          ...on MentionedEvent{createdAt actor{...actor}}
          ...on MilestonedEvent{createdAt actor{...actor} milestoneTitle}
          ...on ParentIssueAddedEvent{createdAt actor{...actor}}
          ...on ParentIssueRemovedEvent{createdAt actor{...actor}}
          ...on PinnedEvent{createdAt actor{...actor}}
          ...on ReferencedEvent{createdAt actor{...actor} commit{oid}}
          ...on RenamedTitleEvent{createdAt actor{...actor} previousTitle currentTitle}
          ...on ReopenedEvent{createdAt actor{...actor}}
          ...on SubIssueAddedEvent{createdAt actor{...actor}}
          ...on SubIssueRemovedEvent{createdAt actor{...actor}}
          ...on SubscribedEvent{createdAt actor{...actor}}
          ...on TransferredEvent{createdAt actor{...actor}}
          ...on UnassignedEvent{createdAt actor{...actor} assignee{...actor}}
          ...on UnlabeledEvent{createdAt actor{...actor} label{name}}
          ...on UnlockedEvent{createdAt actor{...actor}}
          ...on UnmarkedAsDuplicateEvent{createdAt actor{...actor}}
          ...on UnpinnedEvent{createdAt actor{...actor}}
          ...on UnsubscribedEvent{createdAt actor{...actor}}
        }
      }
    }
  }
}
fragment actor on Actor{login ...on User{name databaseId} ...on Bot{databaseId}}
]]

---@param issue Issue
---@param opts { force_refresh?: boolean }|nil
---@param on_done fun(items: IssueConversationItem[]|nil, err: string|nil)
---@return { cancel: fun() }|nil
function M.fetch_conversation(issue, opts, on_done)
	opts = opts or {}
	local slug, number = normalizer.parse_key(issue.key)
	if slug == "" or number == nil then
		on_done(nil, "Invalid issue key")
		return nil
	end

	local cache_key = string.format("github_issues:conversation:%s#%d", slug, number)
	if not opts.force_refresh then
		local cached, ok = cli.get_mem(cache_key)
		if ok then
			on_done(cached, nil)
			return nil
		end
	end

	local owner, name = slug:match("^([^/]+)/(.+)$")
	return cli.gh({
		"api",
		"graphql",
		"--paginate",
		"--slurp",
		"-f",
		"owner=" .. owner,
		"-f",
		"name=" .. name,
		"-F",
		"number=" .. number,
		"-f",
		"query=" .. TIMELINE_QUERY,
	}, function(result, err)
		if err or type(result) ~= "table" then
			on_done(nil, err or "Failed to fetch issue conversation")
			return
		end

		local items, events = {}, {}
		for index, page in ipairs(result) do
			local raw_issue = json.safe_table(json.safe_table(json.safe_table(page.data).repository).issue)
			-- Every page repeats the issue itself, so its description is taken from the first one.
			local description = index == 1 and normalizer.to_comment(raw_issue) or nil
			if description then
				table.insert(items, {
					id = "description",
					kind = "description",
					created_at = description.created_at,
					entity = description,
				})
			end
			for _, node in ipairs(json.safe_table(json.safe_table(raw_issue.timelineItems).nodes)) do
				if node.__typename == "IssueComment" then
					local comment = normalizer.to_comment(node)
					if comment then
						table.insert(items, {
							id = "comment:" .. comment.id,
							kind = "comment",
							created_at = comment.created_at,
							entity = comment,
						})
					end
				else
					local entry = normalizer.to_timeline_entry(node)
					if entry then
						table.insert(events, {
							id = table.concat({ "activity", entry.date, #events + 1 }, ":"),
							kind = "activity",
							created_at = entry.date,
							entity = entry,
						})
					end
				end
			end
		end
		vim.list_extend(items, events)

		cli.set_mem(cache_key, items)
		on_done(items, nil)
	end, {
		action = "Fetch issue conversation timeline",
		slug = slug,
		number = number,
	})
end

return M
