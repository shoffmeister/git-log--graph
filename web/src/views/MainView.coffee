import { ref, computed, watch, nextTick, onMounted } from 'vue'
import * as store from './store.coffee'
import { show_error_message } from '../bridge.coffee'
import { is_truthy } from './types'
import GitInputModel from './GitInput.coffee'
import GitInput from './GitInput.vue'
import GitActionButton from './GitActionButton.vue'
import CommitDetails from './CommitDetails.vue'
import CommitsDetails from './CommitsDetails.vue'
import SVGVisualization from './SVGVisualization.vue'
import ASCIIVisualization from './ASCIIVisualization.vue'
import AllBranches from './AllBranches.vue'
import SelectedGitAction from './SelectedGitAction.vue'
import RefTip from './RefTip.vue'
import RepoSelection from './RepoSelection.vue'
``###*
# @typedef {import('./types').Commit} Commit
###
###* @template T @typedef {import('vue').Ref<T>} Ref ###

export default
	components: { CommitDetails, CommitsDetails, GitInput, GitActionButton, SVGVisualization, ASCIIVisualization, AllBranches, RefTip, SelectedGitAction, RepoSelection }
	setup: ->
		``###* @type {string[]} ###
		default_selected_commits_hashes = []
		selected_commits_hashes = store.stateful_computed 'selected-commits-hashes', default_selected_commits_hashes
		selected_commits = computed
			get: =>
				selected_commits_hashes.value
					.map (hash) => filtered_commits.value.find (commit) => commit.hash == hash
					.filter is_truthy
			set: (commits) =>
				selected_commits_hashes.value = commits.map (commit) => commit.hash
		selected_commit = computed =>
			if selected_commits.value.length == 1
				selected_commits.value[0]
		commit_clicked = (###* @type Commit ### commit, ###* @type MouseEvent ### event) =>
			return if not commit.hash
			selected_index = selected_commits.value.indexOf commit
			if event.ctrlKey
				if selected_index > -1
					selected_commits.value = selected_commits.value.filter (_, i) => i != selected_index
				else
					selected_commits.value = [...selected_commits.value, commit]
			else if event.shiftKey
				total_index = filtered_commits.value.indexOf commit
				last_total_index = filtered_commits.value.indexOf selected_commits.value.at(-1)
				if total_index > last_total_index and total_index - last_total_index < 1000
					selected_commits.value = selected_commits.value.concat(filtered_commits.value.slice(last_total_index, total_index+1).filter (commit) =>
						not selected_commits.value.includes commit)
			else
				if selected_index > -1
					selected_commits.value = []
				else
					selected_commits.value = [commit]



		txt_filter = ref ''
		``###* @type {Ref<'filter' | 'jump'>} ###
		txt_filter_type = ref 'filter'
		clear_filter = =>
			txt_filter.value = ''
			if selected_commit.value
				selected_i = filtered_commits.value.findIndex (c) => c == selected_commit.value
				await nextTick()
				scroll_to_item_centered selected_i
		``###* @type {Ref<HTMLElement | null>} ###
		txt_filter_ref = ref null
		txt_filter_filter = (###* @type Commit ### commit) =>
			search_for = txt_filter.value.toLowerCase()
			for str from [commit.subject, commit.hash, commit.author_name, commit.author_email, commit.branch?.id]
				return true if str?.includes(search_for)
		initialized = computed =>
			!! store.commits.value
		filtered_commits = computed =>
			if not txt_filter.value or txt_filter_type.value == 'jump'
				return store.commits.value or []
			(store.commits.value or []).filter txt_filter_filter
		txt_filter_last_i = -1
		document.addEventListener 'keyup', (e) =>
			if e.ctrlKey and e.key == 'f'
				txt_filter_ref.value?.focus()
		select_searched_commit_debouncer = -1
		txt_filter_enter = (###* @type KeyboardEvent ### event) =>
			return if txt_filter_type.value == 'filter'
			if event.shiftKey
				next = [...filtered_commits.value.slice(0, txt_filter_last_i)].reverse().findIndex(txt_filter_filter)
				if next > -1
					next_match_index = txt_filter_last_i - 1 - next
				else
					next_match_index = filtered_commits.value.length - 1
			else
				next = filtered_commits.value.slice(txt_filter_last_i + 1).findIndex(txt_filter_filter)
				if next > -1
					next_match_index = txt_filter_last_i + 1 + next
				else
					next_match_index = 0
			scroll_to_item_centered next_match_index
			txt_filter_last_i = next_match_index
			window.clearTimeout select_searched_commit_debouncer
			select_searched_commit_debouncer = window.setTimeout (=>
				selected_commits.value = [filtered_commits.value[txt_filter_last_i]]
			), 100



		scroll_to_branch_tip = (###* @type string ### branch_id) =>
			first_branch_commit_i = filtered_commits.value.findIndex (commit) =>
				# Only applicable if virtual branches are excluded as these don't have a tip. Otherwise, each vis would need to be traversed
				commit.refs.some (ref) => ref.id == branch_id
			if first_branch_commit_i == -1
				return show_error_message "No commit found for branch #{branch_id}. Not enough commits loaded?"
			scroll_to_item_centered first_branch_commit_i
			# Not only scroll to tip, but also select it, so the behavior is equal to clicking on
			# a branch name in a commit's ref list.
			selected_commits.value = [filtered_commits.value[first_branch_commit_i]]
		scroll_to_commit = (###* @type string ### hash) =>
			commit_i = filtered_commits.value.findIndex (commit) =>
				commit.hash == hash
			if commit_i == -1
				return show_error_message "No commit found for hash #{hash}. No idea why :/"
			scroll_to_item_centered commit_i
			selected_commits.value = [filtered_commits.value[commit_i]]
		scroll_to_top = =>
			commits_scroller_ref.value?.scrollToItem 0



		``###* @type {Ref<GitInputModel | null>} ###
		git_input_ref = ref null
		store.main_view_git_input_ref.value = git_input_ref
		log_action =
			# rearding the -greps: Under normal circumstances, when showing stashes in
			# git log, each of the stashes 2 or 3 parents are being shown. That because of
			# git internals, but they are completely useless to the user.
			# Could not find any easy way to skip those other than de-grepping them, TODO:.
			# Something like `--exclude-commit=stash@{...}^2+` doesn't exist.
			args: "log --graph --oneline --pretty={EXT_FORMAT} -n 15000 --skip=0 --all {STASH_REFS} --invert-grep --grep=\"^untracked files on \" --grep=\"^index on \""
			options: [
				{ value: '--decorate-refs-exclude=refs/remotes', default_active: false, info: 'Hide remote branches' }
				{ value: '--grep="^Merge branch \'" --grep="^Merge remote tracking branch \'" --grep="^Merge pull request"', default_active: false, info: 'Hide merge commits' }
				{ value: '--date-order', default_active: false, info: 'Show no parents before all of its children are shown, but otherwise show commits in the commit timestamp order.' }
				{ value: '--author-date-order', default_active: true, info: 'Show no parents before all of its children are shown, but otherwise show commits in the author timestamp order.' }
				{ value: '--topo-order', default_active: false, info: 'Show no parents before all of its children are shown, and avoid showing commits on multiple lines of history intermixed.' }
				{ value: '--reflog', default_active: false, info: 'Pretend as if all objects mentioned by reflogs are listed on the command line as <commit>. / Reference logs, or "reflogs", record when the tips of branches and other references were updated in the local repository. Reflogs are useful in various Git commands, to specify the old value of a reference. For example, HEAD@{2} means "where HEAD used to be two moves ago", master@{one.week.ago} means "where master used to point to one week ago in this local repository", and so on. See gitrevisions(7) for more details.' }
				{ value: '--simplify-by-decoration', default_active: false, info: 'Allows you to view only the big picture of the topology of the history, by omitting commits that are not referenced by some branch or tag. Can be useful for very large repositories.' }

			]
			config_key: "main-log"
			immediate: true
		is_first_log_run = true
		### Performance bottlenecks, in this order: Renderer (solved with virtual scroller, now always only a few ms), git cli (depends on both repo size and -n option and takes between 0 and 30 seconds, only because of its --graph computation), processing/parsing/transforming is about 1%-20% of git.
		This function exists so we can modify the args before sending to git, otherwise
		GitInput would have done the git call ###
		run_log = (###* @type string ### log_args) =>
			await store.git_run_log(log_args)
			await new Promise (ok) => setTimeout(ok, 0)
			if is_first_log_run
				first_selected_hash = selected_commits.value[0]?.hash
				if first_selected_hash
					scroll_to_commit first_selected_hash
				is_first_log_run = false
			else
				if selected_commit.value
					new_commit = filtered_commits.value.find (commit) =>
						commit.hash == selected_commit.value?.hash
					if new_commit
						selected_commits.value = [new_commit]
				commits_scroller_ref.value?.scrollToItem scroll_item_offset




		``###* @type {Ref<any | null>} ###
		commits_scroller_ref = ref null
		``###* @type {Ref<Commit[]>} ###
		visible_commits = ref []
		scroll_item_offset = 0
		commits_scroller_updated = (###* @type number ### start_index, ###* @type number ### end_index) =>
			scroll_item_offset = start_index
			commits_start_index = if scroll_item_offset < 3 then 0 else scroll_item_offset + 2
			visible_commits.value = filtered_commits.value.slice(commits_start_index, end_index)
		scroller_on_wheel = (###* @type WheelEvent ### event) =>
			return if store.config.value['disable-scroll-snapping']
			event.preventDefault()
			commits_scroller_ref.value?.scrollToItem scroll_item_offset + Math.round(event.deltaY / 20) + 2
		scroller_on_keydown = (###* @type KeyboardEvent ### event) =>
			return if store.config.value['disable-scroll-snapping']
			if event.key == 'ArrowDown'
				event.preventDefault()
				commits_scroller_ref.value?.scrollToItem scroll_item_offset + 3
			else if event.key == 'ArrowUp'
				event.preventDefault()
				commits_scroller_ref.value?.scrollToItem scroll_item_offset + 1
		scroll_to_item_centered = (###* @type number ### index) =>
			commits_scroller_ref.value?.scrollToItem index - Math.floor(visible_commits.value.length / 2) + 2




		watch visible_commits, =>
			visible_cp = [...visible_commits.value] # to avoid race conditions
				.filter (commit) => commit.hash and not commit.stats
			if not visible_cp.length then return
			await store.update_commit_stats(visible_cp)
		visible_branches = computed =>
			[...new Set(visible_commits.value
				.flatMap (commit) =>
					commit.vis.map (v) => v.branch)]
			.filter(is_truthy)
			.filter (branch) => not branch.virtual
		visible_branch_tips = computed =>
			[...new Set(visible_commits.value
				.flatMap (commit) =>
					commit.refs)]
			.filter (ref) =>
				# @ts-ignore
				ref.type == 'branch' and not ref.virtual
		invisible_branch_tips_of_visible_branches = computed =>
			# alternative: (visible_commits.value[0]?.refs.filter (ref) => ref.type == 'branch' and not ref.virtual and not visible_branch_tips.value.includes(ref)) or []
			visible_branches.value.filter (branch) =>
				not visible_branch_tips.value.includes branch




		# To paint a nice gradient between branches at the top and the vis below:
		connection_fake_commit = computed =>
			commit = visible_commits.value[0]
			return null if not commit
			{
				...commit
				scroll_height: 110
				refs: []
				vis: commit.vis.map (v) => {
					...v
					char:
						if v.branch and invisible_branch_tips_of_visible_branches.value.includes(v.branch)
							switch v.char
								when '*', '|', '⎽*', '⎽|', '*⎽', '|⎽' then '|'
								when '⎺*', '⎺|', '\\', '.', '-'       then '⎽|'
								when '*⎺', '|⎺', '/'                  then '|⎽'
								when '⎺\\', '⎺\\⎽'                    then '⎽⎽|'
								when '/⎺'                             then '|⎽⎽'
								else ' '
						else ' '
				}
			}
		invisible_branch_tips_of_visible_branches_elems = computed =>
			row = -1
			(connection_fake_commit.value?.vis
				.map (v, i) =>
					return null if not v.branch or v.char == ' '
					row++
					row = 0 if row > 5
					branch: v.branch
					bind:
						style:
							left: 0 + store.vis_v_width.value * i + 'px'
							top: 0 + row * 19 + 'px'
				.filter(is_truthy)) or []



		visualization_component = computed =>
			if store.config.value['branch-visualization'] == 'svg'
				SVGVisualization
			else
				ASCIIVisualization




		global_actions = computed =>
			store.global_actions.value



		onMounted =>
			# didn't work with @keyup.escape.native on the components root element
			# when focus was in a sub component (??) so doing this instaed:
			document.addEventListener 'keyup', (e) =>
				if e.key == "Escape"
					selected_commits.value = []
			commits_scroller_ref.value.$el.focus()


		# It didn't work with normal context binding to the scroller's commit elements, either a bug
		# of context-menu update or I misunderstood something about vue-virtual-scroller, but this
		# works around it reliably (albeit uglily)
		commit_context_menu_provider = computed => (###* @type MouseEvent ### event) =>
			el = event.target
			return if el not instanceof HTMLElement and el not instanceof SVGElement
			while el.parentElement and not el.parentElement.classList.contains('commit')
				el = el.parentElement
			return if not el.parentElement
			hash = el.parentElement.dataset.commitHash
			throw "commit context menu element has no hash?" if not hash
			store.commit_actions(hash).value.map (action) =>
				label: action.title
				icon: action.icon
				action: =>
					store.selected_git_action.value = action



		config_show_quick_branch_tips = computed =>
			not store.config.value['hide-quick-branch-tips']



		{
			initialized
			filtered_commits
			branches: store.branches
			vis_max_amount: store.vis_max_amount
			head_branch: store.head_branch
			git_input_ref
			run_log
			log_action
			commits_scroller_updated
			visible_branches
			commits_scroller_ref
			scroll_to_branch_tip
			scroll_to_commit
			scroll_to_top
			selected_commit
			selected_commits
			commit_clicked
			txt_filter
			txt_filter_ref
			txt_filter_type
			txt_filter_enter
			clear_filter
			global_actions
			combine_branches_to_branch_name: store.combine_branches_to_branch_name
			combine_branches_from_branch_name: store.combine_branches_from_branch_name
			combine_branches_actions: store.combine_branches_actions
			invisible_branch_tips_of_visible_branches
			invisible_branch_tips_of_visible_branches_elems
			connection_fake_commit
			refresh_main_view: store.refresh_main_view
			selected_git_action: store.selected_git_action
			commit_context_menu_provider
			git_status: store.git_status
			scroller_on_wheel
			scroller_on_keydown
			config_show_quick_branch_tips
			visualization_component
		}