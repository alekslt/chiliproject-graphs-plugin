require 'SVG/Graph/TimeSeries'
#require 'Engines::RailsExtensions::AssetHelpers'
class GraphsController < ApplicationController

    unloadable

    ############################################################################
    # Initialization
    ############################################################################

    menu_item :issues, :only => [:issue_growth, :old_issues]

    before_filter :authorize_global, :except => [:recent_status_changes_graph, :recent_assigned_to_changes_graph, :target_version_status_graph, :target_version_status_graphjs, :target_version_cycletimejs_graph]
    before_filter :find_version, :only => [:target_version_graph, :target_version_status_graph, :target_version_status_graphjs, :target_version_cycletimejs_graph]
    before_filter :size_args_check, :only => [:target_version_status_graphjs, :target_version_cycletimejs_graph]
    before_filter :confirm_issues_exist, :only => [:issue_growth]
    before_filter :find_optional_project, :only => [:issue_growth_graph]
    before_filter :find_open_issues, :only => [:old_issues, :issue_age_graph]

    helper IssuesHelper

    ############################################################################
    # My Page block graphs
    ############################################################################

    # Displays a ring of issue assignement changes around the current user
    def recent_assigned_to_changes_graph
      if User.current.allowed_to?(:view_graphs, nil, :global => true)
        # Get the top visible projects by issue count
        sql = " select u1.id as old_user, u2.id as new_user, count(*) as changes_count"
        sql << " from journals as j"
        sql << " left join journal_details as jd on j.id = jd.journal_id"
        sql << " left join users as u1 on jd.old_value = u1.id"
        sql << " left join users as u2 on jd.value = u2.id"
        sql << " where j.type = 'IssueJournal' and prop_key = 'assigned_to_id' and  DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 DAY) <= j.created_at"
        sql << " and (u1.id = #{User.current.id} or u2.id = #{User.current.id})"
        sql << " and u1.id <> 0 and u2.id <> 0"
        sql << " group by old_value, value"
        @assigned_to_changes = ActiveRecord::Base.connection.select_all(sql)
        user_ids = @assigned_to_changes.collect { |change| [change["old_user"].to_i, change["new_user"].to_i] }.flatten.uniq
        user_ids.delete(User.current.id)
        @users = User.find(:all, :conditions => "id IN ("+user_ids.join(',')+")").index_by { |user| user.id } unless user_ids.empty?
        headers["Content-Type"] = "image/svg+xml"
        render :layout => false
      else
        render :text => t("warning_not_allowed_block")
      end
    end

    # Displays a ring of issue status changes
    def recent_status_changes_graph
      if User.current.allowed_to?(:view_graphs, nil, :global => true)
        # Get the top visible projects by issue count
        sql = " select is1.id as old_status, is2.id as new_status, count(*) as changes_count"
        sql << " from journals as j"
        sql << " left join journal_details as jd on j.id = jd.journal_id"
        sql << " left join issue_statuses as is1 on jd.old_value = is1.id"
        sql << " left join issue_statuses as is2 on jd.value = is2.id"
        sql << " where j.type = 'IssueJournal' and prop_key = 'status_id' and  DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 DAY) <= created_at"
        sql << " group by old_value, value"
        sql << " order by is1.position, is2.position"
        @status_changes = ActiveRecord::Base.connection.select_all(sql)
        @issue_statuses = IssueStatus.find(:all).sort { |a,b| a.position<=>b.position }
        headers["Content-Type"] = "image/svg+xml"
        render :layout => false
      else
        render :text => t("warning_not_allowed_block")
      end
    end


    ############################################################################
    # Graph pages
    ############################################################################

    # Displays total number of issues over time
    def issue_growth
    end

    # Displays created vs update date on open issues over time
    def old_issues
        @issues_by_created_on = @issues.sort {|a,b| a.created_on<=>b.created_on}
        @issues_by_updated_on = @issues.sort {|a,b| a.updated_on<=>b.updated_on}
    end


    ############################################################################
    # Embedded graphs for graph pages
    ############################################################################

    # Displays projects by total issues over time
    def issue_growth_graph

        # Initialize the graph
        graph = SVG::Graph::TimeSeries.new({
            :area_fill => true,
            :height => 300,
            :min_y_value => 0,
            :no_css => true,
            :show_x_guidelines => true,
            :scale_x_integers => true,
            :scale_y_integers => true,
            :show_data_points => false,
            :show_data_values => false,
            :stagger_x_labels => true,
            :style_sheet => plugin_asset_path('chiliproject-graphs-plugin', 'stylesheets', 'issue_growth.css'),
            :width => 720,
            :x_label_format => "%Y-%m-%d"
        })

        # Get the top visible projects by issue count
        sql = "SELECT project_id, COUNT(*) as issue_count"
        sql << " FROM issues"
        sql << " LEFT JOIN #{Project.table_name} ON #{Issue.table_name}.project_id = #{Project.table_name}.id"
        sql << " WHERE (%s)" % Project.allowed_to_condition(User.current, :view_issues)
        unless @project.nil?
            sql << " AND (project_id = #{@project.id}"
            sql << "    OR project_id IN (%s)" % @project.descendants.active.visible.collect { |p| p.id }.join(',') unless @project.descendants.active.visible.empty?
            sql << " )"
        end
        sql << " GROUP BY project_id"
        sql << " ORDER BY issue_count DESC"
        sql << " LIMIT 6"
        top_projects = ActiveRecord::Base.connection.select_all(sql).collect { |p| p["project_id"] }

        # Get the issues created per project, per day
        sql = "SELECT project_id, date(#{Issue.table_name}.created_on) as date, COUNT(*) as issue_count"
        sql << " FROM #{Issue.table_name}"
        sql << " WHERE project_id IN (%s)" % top_projects.compact.join(',')
        sql << " GROUP BY project_id, date"
        issue_counts = ActiveRecord::Base.connection.select_all(sql).group_by { |c| c["project_id"] }

        # Generate the created_on lines
        top_projects.each do |project_id, total_count|
            counts = issue_counts[project_id].sort { |a,b| a["date"]<=>b["date"] }
            created_count = 0
            created_on_line = Hash.new
            created_on_line[(Date.parse(counts.first["date"].to_s)-1).to_s] = 0
            counts.each { |count| created_count += count["issue_count"].to_i; created_on_line[count["date"].to_s] = created_count }
            created_on_line[Date.today.to_s] = created_count
            graph.add_data({
                :data => created_on_line.sort.flatten,
                :title => Project.find(project_id).to_s
            })
        end

        # Compile the graph
        headers["Content-Type"] = "image/svg+xml"
        send_data(graph.burn, :type => "image/svg+xml", :disposition => "inline")
    end


    # Displays issues by creation date, cumulatively
    def issue_age_graph

        # Initialize the graph
        graph = SVG::Graph::TimeSeries.new({
            :area_fill => true,
            :height => 300,
            :min_y_value => 0,
            :no_css => true,
            :show_x_guidelines => true,
            :scale_x_integers => true,
            :scale_y_integers => true,
            :show_data_points => false,
            :show_data_values => false,
            :stagger_x_labels => true,
            :style_sheet => plugin_asset_path('chiliproject-graphs-plugin', 'stylesheets', 'issue_age.css'),
            :width => 720,
            :x_label_format => "%b %d"
        })

        # Group issues
        issues_by_created_on = @issues.group_by {|issue| issue.created_on.to_date }.sort
        issues_by_updated_on = @issues.group_by {|issue| issue.updated_on.to_date }.sort

        # Generate the created_on line
        created_count = 0
        created_on_line = Hash.new
        issues_by_created_on.each { |created_on, issues| created_on_line[(created_on-1).to_s] = created_count; created_count += issues.size; created_on_line[created_on.to_s] = created_count }
        created_on_line[Date.today.to_s] = created_count
        graph.add_data({
            :data => created_on_line.sort.flatten,
            :title => l(:field_created_on)
        }) unless issues_by_created_on.empty?

        # Generate the closed_on line
        updated_count = 0
        updated_on_line = Hash.new
        issues_by_updated_on.each { |updated_on, issues| updated_on_line[(updated_on-1).to_s] = updated_count; updated_count += issues.size; updated_on_line[updated_on.to_s] = updated_count }
        updated_on_line[Date.today.to_s] = updated_count
        graph.add_data({
            :data => updated_on_line.sort.flatten,
            :title => l(:field_updated_on)
        }) unless issues_by_updated_on.empty?

        # Compile the graph
        headers["Content-Type"] = "image/svg+xml"
        send_data(graph.burn, :type => "image/svg+xml", :disposition => "inline")
    end

    # Displays open and total issue counts over time
    def target_version_graph

        # Initialize the graph
        graph = SVG::Graph::TimeSeries.new({
            :area_fill => true,
            :height => 300,
            :no_css => true,
            :show_x_guidelines => true,
            :scale_x_integers => true,
            :scale_y_integers => true,
            :show_data_points => true,
            :show_data_values => false,
            :stagger_x_labels => true,
            :style_sheet => plugin_asset_path('chiliproject-graphs-plugin', 'stylesheets', 'target_version.css'),
            :width => 800,
            :x_label_format => "%b %d"
        })


        # Group issues
        issues_by_created_on = @version.fixed_issues.group_by {|issue| issue.created_on.to_date }.sort
        issues_by_updated_on = @version.fixed_issues.group_by {|issue| issue.updated_on.to_date }.sort
        issues_by_closed_on = @version.fixed_issues.collect {|issue| issue if issue.closed? }.compact.group_by {|issue| issue.updated_on.to_date }.sort

        # Set the scope of the graph
        scope_end_date = issues_by_updated_on.last.first
        scope_end_date = @version.effective_date if !@version.effective_date.nil? && @version.effective_date > scope_end_date
        scope_end_date = Date.today if !@version.completed?
        line_end_date = Date.today
        line_end_date = scope_end_date if scope_end_date < line_end_date

        # Generate the created_on line
        created_count = 0
        created_on_line = Hash.new
        issues_by_created_on.each { |created_on, issues| created_on_line[(created_on-1).to_s] = created_count; created_count += issues.size; created_on_line[created_on.to_s] = created_count }
        created_on_line[scope_end_date.to_s] = created_count
        graph.add_data({
            :data => created_on_line.sort.flatten,
            :title => l(:label_total).capitalize
        })

        # Generate the closed_on line
        closed_count = 0
        closed_on_line = Hash.new
        issues_by_closed_on.each { |closed_on, issues| closed_on_line[(closed_on-1).to_s] = closed_count; closed_count += issues.size; closed_on_line[closed_on.to_s] = closed_count }
        closed_on_line[line_end_date.to_s] = closed_count
        graph.add_data({
            :data => closed_on_line.sort.flatten,
            :title => l(:label_closed_issues).capitalize
        })

        # Add the version due date marker
        graph.add_data({
            :data => [@version.effective_date.to_s, created_count],
            :title => l(:field_due_date).capitalize
        }) unless @version.effective_date.nil?


        # Compile the graph
        headers["Content-Type"] = "image/svg+xml"
        send_data(graph.burn, :type => "image/svg+xml", :disposition => "inline")
    end





    # Displays open and total issue counts over time
    def target_version_status_graph

        size='small'
        size = params[:size] if params.has_key?(:size)

        height = 300
        width = 800


        case size
        when 'small'
            # Defaults
        when 'large'
            height = 500
            width = 1333
         when 'large-hd'
            height = 712
            width = 1900
        end

        # Initialize the graph
        graph = SVG::Graph::TimeSeries.new({
            :area_fill => true,
            :height => height,
            :width => width,
            :no_css => true,
            :show_x_guidelines => true,
            :scale_x_integers => true,
            :scale_y_integers => true,
            :show_data_points => false,
            :show_data_values => false,
            :stagger_x_labels => true,
            :min_y_value => 0,
            :style_sheet => plugin_asset_path('chiliproject-graphs-plugin', 'stylesheets', 'target_state.css'),

            :x_label_format => "%Y %b %d",
        })

        curr_status = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
        sorted_status = [-1,-1,-1,-1,-1,-1,-1,-1,-1,-1]

        issues_by_date_status = {}
        issues_by_status_date = {}
        
        earliest_issue_date = Date.today

        @version.fixed_issues.each { |issue|
            #puts "IssueId: #{issue.id}\n"
            issue_status = issue_history(issue)
            #puts "IssueStatuses: #{issue_status}\n"

            issue_status.each do |date, status_changes|
                parsedDate = date

                if parsedDate < earliest_issue_date
                    earliest_issue_date = parsedDate
                end

                issues_by_date_status[parsedDate] ||= {}

                status_changes["status"].each do | status |
                    
                    from_state = Integer(status[:old])
                    to_state = Integer(status[:new])
                    #puts "    Date: #{parsedDate} (#{parsedDate.class}) ||  State: #{from_state} => #{to_state} \n"
                    
                    issues_by_status_date[from_state] ||= {}
                    issues_by_status_date[to_state] ||= {}

                    if issues_by_date_status[parsedDate].has_key?(from_state)
                        issues_by_date_status[parsedDate][from_state] -= 1
                    else
                        issues_by_date_status[parsedDate][from_state] = -1
                    end

                    if issues_by_date_status[parsedDate].has_key?(to_state)
                        if from_state == to_state
                            issues_by_date_status[parsedDate][to_state] = 1
                        else
                            issues_by_date_status[parsedDate][to_state] += 1
                        end
                    else
                        issues_by_date_status[parsedDate][to_state] = 1
                    end

                    if issues_by_status_date[from_state].has_key?(parsedDate)
                        issues_by_status_date[from_state][parsedDate] -= 1
                    else
                        issues_by_status_date[from_state][parsedDate] = -1
                    end

                    if issues_by_status_date[to_state].has_key?(parsedDate)
                        issues_by_status_date[to_state][parsedDate] += 1
                    else
                        issues_by_status_date[to_state][parsedDate] = 1
                    end
                    #puts "    Arr: #{issues_by_date_status[parsedDate].inspect}\n"
                end
            end
        }

        


        issues_by_status_date.sort.each do |status_id, statecount|
            next if status_id == 0
            sobj = IssueStatus.find_by_id(status_id)
            sorted_status[sobj.position] = status_id
        end

        sorted_status = sorted_status.reverse

        #puts "Sorts by: #{sorted_status.inspect}\n"

        # Set the scope of the graph
        issues_by_updated_on = @version.fixed_issues.group_by {|issue| issue.updated_on.to_date }.sort
        scope_end_date = issues_by_updated_on.last.first
        scope_end_date = @version.effective_date if !@version.effective_date.nil? && @version.effective_date > scope_end_date
        scope_end_date = Date.today if !@version.completed?
       
        scope_start_date = @version.start_date
        if params.has_key?(:lastdays)
            lastdate = (scope_end_date-Integer(params[:lastdays]))
            scope_start_date = lastdate
        end
        
        line_end_date = Date.today
        line_end_date = scope_end_date if scope_end_date < line_end_date
        
        
        issues_by_date_status_sum = {}

        #puts "Calculating from #{earliest_issue_date} to  #{scope_end_date}\n"

        (earliest_issue_date..scope_end_date).each do |date_today|
            #puts "Date: #{date_today}\n"
            if issues_by_date_status.has_key?(date_today)
                issues_by_date_status[date_today].each do |status, diff|
                    next if status == 0
                    curr_status[status] += diff
                end
            end

            issues_by_date_status_sum[date_today] ||= {}

            sorted_status.each do |status_id|
                next if status_id == -1

                curr_total = 0
                sorted_status.each do |id|
                    next if id == -1
                    curr_total += curr_status[id]
                    if id == status_id
                        break
                    end
                end
                #puts "  S_id: #{status_id} = #{curr_total}\n"
                issues_by_date_status_sum[date_today][status_id] = curr_total
            end

        end

        issues_by_status_date_sum = {}

        issues_by_date_status_sum.each do |date, status_and_count|

            status_and_count.each do |status_id, num|
                if status_id != 0
                    issues_by_status_date_sum[status_id] ||= {}
                    issues_by_status_date_sum[status_id][date] = num
                end
            end


        end
        
        sorted_status.reverse.each do |status_id|
            next if status_id == -1

            date_and_count = issues_by_status_date_sum[status_id]

            status_line = Hash.new
            date_and_count.each do |changed_on, num|
                if scope_start_date.nil? || scope_start_date <= changed_on
                    day = changed_on.to_s
                    status_line[day] = num
                end  
            end

            next if status_line.count == 0

            status_instance = IssueStatus.find_by_id(status_id)
            status_text = "Unknown: #{status_id}"
            status_text = status_instance.name unless status_instance.nil?

            puts "Line(#{status_id} : #{status_text}"
            graph.add_data({
                :data => status_line.sort.flatten,
                :title => status_text
            })

        end

        # Add the version due date marker
        # created_count = 5
        #graph.add_data({
        #    :data => [@version.effective_date.to_s, created_count],
        #    :title => l(:field_due_date).capitalize
        #}) unless @version.effective_date.nil?

        # Compile the graph
        headers["Content-Type"] = "image/svg+xml"
        send_data(graph.burn, :type => "image/svg+xml", :disposition => "inline")
    end



    def size_args_check
        size='small'
        size = params[:size] if params.has_key?(:size)

        @height = 300
        @width = 700


        case size
        when 'small'
            # Defaults
        when 'large'
            @height = 500
            @width = 1333
         when 'large-hd'
            @height = 712
            @width = 1900
        end
    end

    def target_version_status_graphjs
        curr_status = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
        sorted_status = [-1,-1,-1,-1,-1,-1,-1,-1,-1,-1]

        issues_by_date_status = {}
        issues_by_status_date = {}
        
        earliest_issue_date = Date.today.to_time.to_i
        latest_issue_date = 0

        @version.fixed_issues.each { |issue|
            #puts "IssueId: #{issue.id}\n"
            issue_status = issue_history(issue)
            #puts "IssueStatuses: #{issue_status}\n"

            issue_status.each do |date, status_changes|
                parsedDate = date

                if parsedDate < earliest_issue_date
                    earliest_issue_date = parsedDate
                end

                if parsedDate > latest_issue_date
                    latest_issue_date = parsedDate
                end
                

                issues_by_date_status[parsedDate] ||= {}

                status_changes["status"].each do | status |
                    
                    from_state = Integer(status[:old])
                    to_state = Integer(status[:new])
                    #puts "    Date: #{parsedDate} (#{parsedDate.class}) ||  State: #{from_state} => #{to_state} \n"
                    
                    issues_by_status_date[from_state] ||= {}
                    issues_by_status_date[to_state] ||= {}

                    if issues_by_date_status[parsedDate].has_key?(from_state)
                        issues_by_date_status[parsedDate][from_state] -= 1
                    else
                        issues_by_date_status[parsedDate][from_state] = -1
                    end

                    if issues_by_date_status[parsedDate].has_key?(to_state)
                        if from_state == to_state
                            issues_by_date_status[parsedDate][to_state] = 1
                        else
                            issues_by_date_status[parsedDate][to_state] += 1
                        end
                    else
                        issues_by_date_status[parsedDate][to_state] = 1
                    end

                    if issues_by_status_date[from_state].has_key?(parsedDate)
                        issues_by_status_date[from_state][parsedDate] -= 1
                    else
                        issues_by_status_date[from_state][parsedDate] = -1
                    end

                    if issues_by_status_date[to_state].has_key?(parsedDate)
                        issues_by_status_date[to_state][parsedDate] += 1
                    else
                        issues_by_status_date[to_state][parsedDate] = 1
                    end
                    #puts "    Arr: #{issues_by_date_status[parsedDate].inspect}\n"
                end
            end
        }

        


        issues_by_status_date.sort.each do |status_id, statecount|
            next if status_id == 0
            sobj = IssueStatus.find_by_id(status_id)
            sorted_status[sobj.position] = status_id
        end

        @sorted_status = sorted_status.reverse

        #puts "Sorts by: #{sorted_status.inspect}\n"

        # Set the scope of the graph
        issues_by_updated_on = @version.fixed_issues.group_by {|issue| issue.updated_on.to_date }.sort
        @scope_end_date = Date.today
        @scope_end_date = issues_by_updated_on.last.first if !@issues_by_updated_on.nil? 
        @scope_end_date = @version.effective_date if !@version.effective_date.nil? && @version.effective_date > @scope_end_date
        @scope_end_date = Date.today if !@version.completed?
       
        @scope_start_date = Date.today
        @scope_start_date = @version.start_date if !@version.start_date.nil?
        if params.has_key?(:lastdays)
            lastdate = (@scope_end_date-Integer(params[:lastdays]))
            @scope_start_date = lastdate
        end
        
        # @line_end_date = Date.today
        # @line_end_date = @scope_end_date if @scope_end_date < @line_end_date

        @scope_start_date = @scope_start_date.to_time.to_i
        @scope_end_date = @scope_end_date.to_time.to_i
        
        issues_by_date_status_sum = {}

        #puts "Calculating from #{earliest_issue_date} to  #{scope_end_date}\n"

        #(earliest_issue_date..@scope_end_date).each do |date_today|
        ##    #puts "Date: #{date_today}\n"
        #    if issues_by_date_status.has_key?(date_today)
        #        issues_by_date_status[date_today].each do |status, diff|
        #            next if status == 0
        #            curr_status[status] += diff
        #        end
        #    end
#
 #           issues_by_date_status_sum[date_today] ||= {}
#
 #           @sorted_status.each do |status_id|
  #              next if status_id == -1
   #             #puts "  S_id: #{status_id} = #{curr_total}\n"
    #            issues_by_date_status_sum[date_today][status_id] = curr_status[status_id]
     #       end

      #  end


        issues_by_date_status.keys.sort.each do |changed_on |
            next if changed_on < earliest_issue_date or changed_on > @scope_end_date

            issues_by_date_status[changed_on].each do |status, diff|
                next if status == 0
                curr_status[status] += diff
            end

            issues_by_date_status_sum[changed_on] ||= {}

            @sorted_status.each do |status_id|
                next if status_id == -1
                #puts "  S_id: #{status_id} = #{curr_total}\n"
                issues_by_date_status_sum[changed_on][status_id] = curr_status[status_id]
            end
        end



        @issues_by_status_date_sum = {}

        issues_by_date_status_sum.each do |date, status_and_count|

            status_and_count.each do |status_id, num|
                if status_id != 0
                    @issues_by_status_date_sum[status_id] ||= {}
                    @issues_by_status_date_sum[status_id][date] = num
                end
            end
        end
        
        #

        # Add a last "row" of status changes on scope_end_date to make the graph look pretty.
        @issues_by_status_date_sum.keys.each do | status_id |
            lastKey = @issues_by_status_date_sum[status_id].keys.sort.last
            lastNum = @issues_by_status_date_sum[status_id][lastKey]
            @issues_by_status_date_sum[status_id][@scope_end_date] = lastNum
#            status_and_count.each do |status_id, num|
#                if status_id != 0
#                    #@issues_by_status_date_sum[status_id] ||= {}##
#
#                    @issues_by_status_date_sum[status_id][date] = num
#                end
#            end
        end

        # @sorted_status.reverse.each do |status_id|
        #     next if status_id == -1

        #     date_and_count = @issues_by_status_date_sum[status_id]

        #     status_line = Hash.new
        #     date_and_count.each do |changed_on, num|
        #         if @scope_start_date.nil? || scope_start_date <= changed_on
        #             day = changed_on.to_s
        #             status_line[day] = num
        #         end  
        #     end

        #     next if status_line.count == 0

        #     status_instance = IssueStatus.find_by_id(status_id)
        #     status_text = "Unknown: #{status_id}"
        #     status_text = status_instance.name unless status_instance.nil?

        #     puts "Line(#{status_id} : #{status_text}"

        #     #graph.add_data({
        #     #    :data => status_line.sort.flatten,
        #     #    :title => status_text
        #     #})

        # end

        # Compile the graph
        headers["Content-Type"] = "text/html"
        render :layout => false
    end


    def target_version_cycletimejs_graph



    end


    ###
    # Journal History stuff #

    def issue_history(issue)
   
        full_journal = {}
        issue.journals.each{|journal|
            date = journal.created_on.to_time.to_i

            ## TODO: SKIP estimated_hours and remaining_hours if not a leaf node
            journal.details.each{| prop, value |
                next unless ['status_id'].include?(prop)

                full_journal[date] ||= {}

                case prop
                when "status_id"
                    full_journal[date]["status"] ||= []
                    full_journal[date]["status"] << {:old => value[0], :new => value[1]}

                    puts "Issue: #{issue}, Date#{date}, From #{value[0]} to #{value[1]}\n"
                else
                  raise "Unhandled property #{prop}"
                end
            }

        }
        return full_journal        
    end

    def statuses
        Hash.new{|h, k|
            s = IssueStatus.find_by_id(k.to_i)
            if s.nil?
                s = IssueStatus.default
                puts "IssueStatus #{k.inspect} not found, using default #{s.id} instead"
            end
            h[k] = {:id => s.id, :open => ! s.is_closed?, :success => s.is_closed? ? (s.default_done_ratio.nil? || s.default_done_ratio == 100) : false }
            h[k]
        }
    end





    ############################################################################
    # Private methods
    ############################################################################
    private

    def confirm_issues_exist
        find_optional_project
        if !@project.nil?
            ids = [@project.id]
            ids += @project.descendants.active.visible.collect(&:id)
            @issues = Issue.visible.find(:first, :conditions => ["#{Project.table_name}.id IN (?)", ids])
        else
            @issues = Issue.visible.find(:first)
        end
    rescue ActiveRecord::RecordNotFound
        render_404
    end

    def find_open_issues
        find_optional_project
        if !@project.nil?
            ids = [@project.id]
            ids += @project.descendants.active.visible.collect(&:id)
            @issues = Issue.visible.find(:all, :include => [:status], :conditions => ["#{IssueStatus.table_name}.is_closed=? AND #{Project.table_name}.id IN (?)", false, ids])
        else
            @issues = Issue.visible.find(:all, :include => [:status], :conditions => ["#{IssueStatus.table_name}.is_closed=?", false])
        end
    rescue ActiveRecord::RecordNotFound
        render_404
    end

    def find_optional_project
        @project = Project.find(params[:project_id]) unless params[:project_id].blank?
        deny_access unless User.current.allowed_to?(:view_issues, @project, :global => true)
    rescue ActiveRecord::RecordNotFound
        render_404
    end

    def find_version
        @version = Version.find(params[:id])
        deny_access unless User.current.allowed_to?(:view_issues, @version.project)
    rescue ActiveRecord::RecordNotFound
        render_404
    end

    # Returns the publicly-addressable relative URI for the given asset, type and plugin
    def plugin_asset_path(plugin_name, type, asset)
        raise "No plugin called '#{plugin_name}' - please use the full name of a loaded plugin." if Engines.plugins[plugin_name].nil?
        "#{ActionController::Base.relative_url_root}/#{Engines.plugins[plugin_name].public_asset_directory}/#{type}/#{asset}"
    end

end
