# Provides a graph on the target version page
class TargetVersionGraphHook < Redmine::Hook::ViewListener
  def view_versions_show_bottom(context = { })
  	if !context[:version].fixed_issues.empty?
  		#output = "<fieldset id='target_version_graph'><legend>#{ l(:label_graphs_total_vs_closed_issues) }</legend>"
      #output << tag("embed", :width => "100%", :height => 300, :type => "image/svg+xml", :src => url_for(:controller => 'graphs', :action => 'target_version_graph', :id => context[:version]))
      #output << "</fieldset>"

      output = "<fieldset id='target_version_graph'>\n"
      output << "<a href=\"" << url_for(:controller => 'graphs', :action => 'target_version_status_graphjs', :id => context[:version]) << "?size=large" << "\">\n"
      output << "<legend>#{ l(:label_graphs_status) }</legend>\n"
      output << content_tag("object", "<p>Your browser does not support the object tag</p>",  :width => "100%", :height => 500, :type => "text/html", :data => url_for(:controller => 'graphs', :action => 'target_version_status_graphjs', :id => context[:version]) << "?size=small" )
      output << "</a>\n"
      output << "</fieldset>\n"

      output << "<fieldset id='target_version_graph_last15'>\n"
      output << "<a href=\"" << url_for(:controller => 'graphs', :action => 'target_version_status_graphjs', :id => context[:version]) << "?size=large&lastdays=15" << "\">\n"
      output << "<legend>#{ l(:label_graphs_status_last) }</legend>\n"
      output << content_tag("object", "<p>Your browser does not support the object tag</p>", :width => "100%", :height => 500, :type => "text/html", :data => url_for(:controller => 'graphs', :action => 'target_version_status_graphjs', :id => context[:version]) << "?size=small&lastdays=15" )
      output << "</a>\n"
      output << "</fieldset>\n"


		return output
	end 
  end
end
