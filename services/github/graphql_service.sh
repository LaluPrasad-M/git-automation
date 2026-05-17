#!/usr/bin/env bash

gh_get_pr_review_threads() {
  local owner="$1" repo_name="$2" pr="$3"
  local threads_query
  threads_query="query(\$owner:String!,\$name:String!,\$number:Int!){repository(owner:\$owner,name:\$name){pullRequest(number:\$number){reviewThreads(first:100){nodes{id isResolved path comments(first:50){nodes{id databaseId body author{login} createdAt}}}}}}}"
  gh api graphql \
    -f query="$threads_query" \
    -F owner="$owner" \
    -F name="$repo_name" \
    -F number="$pr"
}

gh_resolve_review_thread() {
  local thread_id="$1"
  gh api graphql \
    -f query="mutation(\$threadId:ID!){resolveReviewThread(input:{threadId:\$threadId}){thread{id isResolved}}}" \
    -F threadId="$thread_id" >/dev/null
}
