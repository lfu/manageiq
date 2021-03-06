module OpsController::Settings::CapAndU
  extend ActiveSupport::Concern

  def cu_collection_update
    return unless load_edit("cu_edit__collection","replace_cell__explorer")
    cu_collection_get_form_vars
    if params[:button] == "save"
      # C & U collection settings
      Metric::Targets.perf_capture_always = {
        :host_and_cluster => @edit[:new][:all_clusters],
        :storage          => @edit[:new][:all_storages]
      }
      unless @edit[:new][:clusters] == @edit[:current][:clusters] # Check for cluster changes
        @temp[:cl_recs] = EmsCluster.all.inject({}) {|h,cl| h[cl.id] = cl; h}
        @temp[:ho_recs] = Host.all.inject({}) {|h,ho| h[ho.id] = ho; h}
        @edit[:new][:clusters].each do |c|
          cl = @temp[:cl_recs][c[:id]]
          en_list ||= Array.new
          if !session[:all_checked].blank?    # pass list of hosts and cluster that are checked, or pass empty list
            if session[:all_checked] != 0
              all_checked = session[:all_checked].split(',')
              all_checked.each do |item|
                h = item.split(':')
                if h.length > 1 && h[0] == "Cluster_#{c[:id]}"
                  en_list.push(@temp[:ho_recs][h[1].split('_')[1].to_i])
                  en_list.push(cl) unless en_list.include?(cl)
                else
                  en_list.push(cl) if !en_list.include?(cl) && all_checked.include?("Cluster_#{c[:id]}")
                end
              end
            end
            cl.set_perf_collection_object_list(en_list)
          end
        end
      end

      if !@edit[:current][:non_cl_hosts].blank?   # if there are any hosts without clusters
        @edit[:current][:non_cl_hosts].each do |h_id|
          h = Host.find_by_id(h_id[:id])
          h.perf_capture_enabled = @edit[:new][:non_cluster_host_enabled][h.id.to_s] == true
        end
      end

      unless @edit[:new][:storages] == @edit[:current][:storages] # Check for storage changes
        @temp[:st_recs] = Storage.all.inject({}) {|h,st| h[st.id] = st; h}
        @edit[:new][:storages].each_with_index do |s, si|
          if s[:capture] != @edit[:current][:storages][si][:capture]
            ds = @temp[:st_recs][s[:id]]
            ds.perf_capture_enabled = s[:capture] if ds
          end
        end
      end

      add_flash(I18n.t("flash.ops.settings.cu_saved"))
      get_node_info(x_node)
      session[:all_checked] = nil
      replace_right_cell(@nodetype)
      return                                                    # No config file for Visuals yet, just return
      get_node_info(x_node)
      replace_right_cell(@nodetype)
    elsif params[:button] == "reset"
      @changed = false
      session[:all_checked] = nil
      add_flash(I18n.t("flash.edit.reset"), :warning)
      get_node_info(x_node)
      replace_right_cell(@nodetype)
    end
  end

  def cu_collection_field_changed
    return unless load_edit("cu_edit__collection","replace_cell__explorer")
    cu_collection_get_form_vars
    @changed = (@edit[:new] != @edit[:current]) # UI edit form, C&U collection form
    # C&U tab
    # need to create an array of items, if their or their children's capture has been changed then make the changed one blue.
    render :update do |page|                    # Use JS to update the display
      page.replace_html(@refresh_div, :partial=>@refresh_partial) if @refresh_div
      page << "$('clusters_div').#{params[:all_clusters] == "1" ? "hide" : "show"}()" if params[:all_clusters]
      page << "$('storages_div').#{params[:all_storages] == "1" ? "hide" : "show"}()" if params[:all_storages]
      if params[:id] || params[:check_all] #|| (params[:tree_name] == "cu_datastore_tree" && params[:check_all])
        if (params[:id] && params[:id].split('_')[0] == "Datastore") || (params[:tree_name] == "cu_datastore_tree" && params[:check_all])
          @changed_id_list = Array.new
          @unchanged_id_list = Array.new
          @edit[:new][:storages].each_with_index do |s,i|
            if @edit[:new][:storages][i][:capture] != @edit[:current][:storages][i][:capture]
              @changed_id_list.push("Datastore_#{s[:id]}")
            else
              @unchanged_id_list.push("Datastore_#{s[:id]}")
            end
          end
          @changed_id_list.each do |item|
            page << "cfme_dynatree_node_add_class('#{j_str(params[:tree_name])}', '#{j_str(item)}', 'cfme-blue-bold-node')"
          end
          @unchanged_id_list.each do |item|
            page << "cfme_dynatree_node_add_class('#{j_str(params[:tree_name])}', '#{j_str(item)}', 'dynatree-title')"
          end
        else
          @changed_id_list = Array.new
          @unchanged_id_list = Array.new
          @edit[:new][:clusters].each_with_index do |c,i|
            cname = c[:name]
            if @edit[:new][:clusters][i][:capture] != @edit[:current][:clusters][i][:capture]
              @changed_id_list.push("Cluster_#{c[:id]}")
            else
              @unchanged_id_list.push("Cluster_#{c[:id]}")
            end
            @edit[:new][cname.to_sym].each_with_index do |host,j|
              if @edit[:new][cname.to_sym][j][:capture] != @edit[:current][cname.to_sym][j][:capture]
                @changed_id_list.push("Cluster_#{c[:id]}:Host_#{host[:id]}")
              else
                @unchanged_id_list.push("Cluster_#{c[:id]}:Host_#{host[:id]}")
              end
            end
          end
          if !@edit[:current][:non_cl_hosts].blank?   # if there are any hosts without clusters
            if @edit[:new][:non_cluster_host_enabled] == @edit[:current][:non_cluster_host_enabled]
              @unchanged_id_list.push("NonCluster_0")
            else
              @changed_id_list.push("NonCluster_0")
            end
            @edit[:new][:non_cluster_host_enabled].each do |h|
              if @edit[:current][:non_cluster_host_enabled][h[0]] != @edit[:new][:non_cluster_host_enabled][h[0]]
                @changed_id_list.push("NonCluster_0:Host_#{h[0]}")
              else
                @unchanged_id_list.push("NonCluster_0:Host_#{h[0]}")
              end
            end
          end
          @changed_id_list.each do |item|
            page << "cfme_dynatree_node_add_class('#{j_str(params[:tree_name])}', '#{j_str(item)}', 'cfme-blue-bold-node')"
          end
          @unchanged_id_list.each do |item|
            page << "cfme_dynatree_node_add_class('#{j_str(params[:tree_name])}', '#{j_str(item)}', 'dynatree-title')"
          end
        end
        #need to redraw the tree to change node colors
        page << "cfme_dynatree_redraw('#{j_str(params[:tree_name])}')"
      end
      page << javascript_for_miq_button_visibility(@changed)
    end
  end

  private

  def cu_build_edit_screen
    @edit = Hash.new
    @edit[:new] = Hash.new
    @edit[:current] = Hash.new
    @edit[:key] = "cu_edit__collection"
    @edit[:current][:all_clusters] = Metric::Targets.perf_capture_always[:host_and_cluster]
    @edit[:current][:all_storages] = Metric::Targets.perf_capture_always[:storage]
    @edit[:current][:clusters] = Array.new
    @temp[:cl_recs] = Hash.new
    @temp[:cl_hash] = EmsCluster.get_perf_collection_object_list
    @temp[:cl_hash].each_with_index do |h,j|
      cid, cl_hash = h
      c = cl_hash[:cl_rec]
      @temp[:cl_recs][c.id] = c
      enabled = cl_hash[:ho_enabled]
      enabled_host_ids = enabled.collect {|e| e.id}
      hosts = (cl_hash[:ho_enabled] + cl_hash[:ho_disabled]).sort {|a,b| a.name.downcase <=> b.name.downcase}
      cl_enabled = enabled_host_ids.length == hosts.length
      if cl_enabled && !enabled.empty?
        en_flg = true
      else
        en_flg = false
      end
      # cname = "#{c.ext_management_system.name} : " +
      #         (c.parent_datacenter != nil ? "#{c.parent_datacenter.name} : " : "") +
      #         "#{c.name}"
      cname = c.name
      @edit[:current][:clusters].push({:name=>cname,
                                :id=>c.id,
                                :capture=>en_flg}) # grab name, id, and capture setting
      @edit[:current][cname.to_sym] = Array.new
      hosts.each do |h|
        host_capture = enabled_host_ids.include?(h.id.to_i)
        @edit[:current][cname.to_sym].push({:name=>h.name,
                                  :id=>h.id,
                                  :capture=>host_capture})
      end
      flg = true
      count = 0
      @edit[:current][cname.to_sym].each do |h|
        if !h[:capture]
          count += 1          # checking if all hosts are unchecked then cluster capture will be false else unsure
          flg = (count == @edit[:current][cname.to_sym].length) ? false : "unsure"
        end
        @edit[:current][:clusters][j][:capture] = flg
      end
    end
    @edit[:current][:clusters].sort!{|a,b| a[:name]<=>b[:name]}
    build_cl_hosts_tree(@edit[:current][:clusters])

    @edit[:current][:storages] = Array.new
    @temp[:st_recs] = Hash.new
    Storage.in_my_region.all(:include => [:taggings, :tags, :hosts], :select => "id, name, store_type, location").sort{|a,b| a.name.downcase <=> b.name.downcase}.each do |s|
      @temp[:st_recs][s.id] = s
      @edit[:current][:storages].push({:name=>s.name,
                                :id=>s.id,
                                :capture=>s.perf_capture_enabled?,
                                :store_type=>s.store_type,
                                :location=>s.location}) # fields we need
    end
    build_ds_tree(@edit[:current][:storages])
    @edit[:new] = copy_hash(@edit[:current])
    session[:edit] = @edit
  end

  def cu_collection_get_form_vars
    if params[:id]
      nodetype = params[:id].split(':')
      node_type = nodetype.length >= 2 ? nodetype[1].split('_') : nodetype[0].split('_')
    end
    @edit[:new][:all_clusters] = params[:all_clusters] == "1" if params[:all_clusters]
    @edit[:new][:all_storages] = params[:all_storages] == "1" if params[:all_storages]
    if params[:tree_name] == "clhosts_tree"
      session[:all_checked] = @all_checked = params[:all_checked] if params[:all_checked]
    end
    session[:all_checked] = 0 if (params[:tree_name] == "clhosts_tree" && params[:check_all] && params[:check_all] == "false" && !params[:check])  #if uncheck all was selected, and individual clusters werent checked
    if params[:tree_name] == "clhosts_tree"     # User checked/unchecked a cluster tree node
      if params[:check_all]                         #to handle check/uncheck cluster all checkbox
        @edit[:new][:clusters].each do |c|                                  # Check each clustered host
          c[:capture] = params[:check_all] == "true" ? true : false # if cluster checked/unchecked Set C&U flag for all hosts under it as well
          @edit[:new][c[:name].to_sym].each do |h|
            h[:capture] = params[:check_all] == "true" ? true : false # Set C&U flag depending on if checkbox parm is present
          end
        end
        @edit[:new][:non_cl_hosts].each do |h|                                  # Check each non clustered host
          @edit[:new][:non_cluster_host_enabled][h[:id].to_s] = params[:check_all] == "true" ? true : false # Set C&U flag depending on if checkbox parm is present
        end
      else
        @edit[:new][:clusters].each do |c|                                  # Check each cluster
          if node_type[0] == "Cluster" && node_type[1].to_s == c[:id].to_s
            c[:capture] = params[:check] == "true" ? true : false  # if cluster checked/unchecked Set C&U flag for all hosts under it as well
            @edit[:new][c[:name].to_sym].each do |h|
              h[:capture] = params[:check] == "true" ? true : false  # Set C&U flag depending on if checkbox parm is present
            end
          elsif nodetype[0] == "NonCluster_0"
            process_form_vars_for_non_clustered(node_type)
          elsif node_type[0] == "Host"
            @edit[:new][c[:name].to_sym].each do |h|
              if node_type[1].to_i == h[:id].to_i
                h[:capture] = params[:check] == "true" ? true : false  # Set C&U flag depending on if checkbox parm is present
                c[:capture] = false if params[:check] == "0"
              end
            end
          end

          if node_type[0] == "Host"
            flg = true
            count = 0
            @edit[:new][c[:name].to_sym].each do |h|
              if !h[:capture]
                count += 1          # checking if all hosts are unchecked then cluster capture will be false else unsure
                flg = (count == @edit[:new][c[:name].to_sym].length) ? false : "unsure"
              end
              c[:capture] = flg
            end
          end
        end
        # if there are no clusters, handle non-clustered hosts here
        if @edit[:new][:clusters].blank?
          @edit[:new][:non_cluster_host_enabled].each do |h|
            if nodetype[0] == "NonCluster_0"
              process_form_vars_for_non_clustered(node_type)
            end
          end
        end
      end
    end

    if params[:tree_name] == "cu_datastore_tree" # User checked/unchecked a storage tree node
      if params[:check_all]          #to handle check/uncheck storage all checkbox
        @edit[:new][:storages].each do |s|                                        # Check each storage
          s[:capture] = params[:check_all] == "true" ? true : false               # Set C&U flag depending on if checkbox parm is present
        end
      else
        @edit[:new][:storages].each do |s|                                  # Check each storage
          if node_type[0] == "Datastore" && node_type[1].to_s == s[:id].to_s
            s[:capture] = params[:check] == "true" ? true : false # Set C&U flag depending on if checkbox parm is present
          end
        end
      end
    end
  end

  def build_cl_hosts_tree(clusters)
    # Build the Cluster & Hosts tree for the C&U data collection
    cl_hosts = Array.new                          # Array to hold all EMSs
    clusters.each do |c|  # Go thru all of the EMSs
      cl_node = Hash.new                        # Build the ems node
      cl_node[:key] = "Cluster_" + c[:id].to_s
      cl_node[:title] = c[:name]
      cl_node[:tooltip] = c[:name]
      cl_node[:style] = "cursor:default"     # No cursor pointer
      cl_node[:icon] = "cluster.png"
      cl_kids = Array.new
      cl_hash = @temp[:cl_hash][c[:id]]
      cluster = cl_hash[:cl_rec]
      enabled = cl_hash[:ho_enabled]
      enabled_host_ids = Array.new
      enabled.each do |cls|
        if cls.class != EmsCluster
          enabled_host_ids.push(cls.id) unless enabled_host_ids.include?(cls.id)
        end
      end
      hosts = cl_hash[:ho_enabled] + cl_hash[:ho_disabled]
      # checking if any of the hosts in above list aren't enabled, show cluster partially checked
      cl_enabled = enabled_host_ids.length == hosts.length
      if cl_enabled && !enabled.empty?
        cl_node[:select] = true
      elsif enabled.empty?
        cl_node[:select] = false
      else
        cl_node[:select] = -1
      end
      hosts.sort{|a,b| a.name <=> b.name}.each do |h|
        temp = Hash.new
        temp[:key] = "Cluster_" + c[:id].to_s + ":Host_" + h.id.to_s
        temp[:title] = h.name
        temp[:tooltip] = "Host: #{h.name}"
        temp[:style] = "cursor:default"      # No cursor pointer
        temp[:icon] = "host.png"
        temp[:select] = enabled_host_ids.include?(h.id.to_i) ? true : false
        cl_kids.push(temp)
      end
      cl_node[:children] = cl_kids unless cl_kids.empty?
      cl_hosts.push(cl_node)
    end

    ##################### Adding Non-Clustered hosts node
    @edit[:current][:non_cl_hosts] ||= Array.new
    ExtManagementSystem.in_my_region.all.each_with_index do |e,j|
      all = e.non_clustered_hosts
      all.each do |h|
        @edit[:current][:non_cl_hosts].push({:name=>h.name,
                                :id=>h.id,
                                :capture=>h.perf_capture_enabled?}) # grab name, id, and capture setting
      end
    end
    if !@edit[:current][:non_cl_hosts].blank?
      h_node = Hash.new                       # Build the ems node
      h_node[:key] = "NonCluster_0"
      h_node[:title] = "Non-clustered Hosts"
      h_node[:tooltip] = "Non-clustered Hosts"
      h_node[:style] = "cursor:default"      # No cursor pointer
      h_node[:icon] = "host.png"
      count = non_cl_host_capture_state
      if count.to_i == @edit[:current][:non_cl_hosts].length
        h_node[:select] = true
      elsif count.to_i == 0
        h_node[:select] = false
      else
        h_node[:select] = -1
      end
      h_kids = Array.new
      @edit[:current][:non_cl_hosts].each do |h|
        temp = Hash.new
        temp[:key] = "NonCluster_0" + ":Host_" + h[:id].to_s
        temp[:title] = h[:name]
        temp[:tooltip] = "Host: #{h[:name]}"
        temp[:style] = "cursor:default"      # No cursor pointer
        temp[:icon] = "host.png"
        temp[:select] = h[:capture] ? true : false
        h_kids.push(temp)
      end
      h_node[:children] = h_kids unless h_kids.empty?
      cl_hosts.push(h_node)
    end
    ##################### Ending Non-Clustered hosts node

    @temp[:clhosts_tree] = cl_hosts.to_json  # Add ems node array to root of tree
    session[:tree] = "clhosts"
    session[:tree_name] = "clhosts_tree"
  end

  def non_cl_host_capture_state
    @edit[:current][:non_cluster_host_enabled] = Hash.new
    i = 0
    @edit[:current][:non_cl_hosts].each do |h|
      enabled = h[:capture]
      i += 1 if enabled
      @edit[:current][:non_cluster_host_enabled][h[:id].to_s] = enabled unless @edit[:current][:non_cluster_host_enabled].has_key?(h[:id].to_s)
    end
    return i
  end

  def build_ds_tree(storages)
    # Build the Storages tree for the C&U data collection
    ds = Array.new                          # Array to hold all Storages
    # ems_hash = ExtManagementSystem.in_my_region.all.inject({}) {|h,e| h[e.id] = e.name; h}
    storages.each do |s|                    # Go thru all of the Storages
      ds_node = Hash.new                        # Build the storage node
      ds_node[:key] = "Datastore_" + s[:id].to_s
      name = "<b>#{s[:name]}</b> [#{s[:location]}]"
      ds_node[:title] = name
      ds_node[:tooltip] = name
      ds_node[:style] = "cursor:default"     # No cursor pointer
      ds_node[:icon] = "storage.png"
      ds_node[:select] = s[:capture] == true ? true :false

      children = Array.new
      st = @temp[:st_recs][s[:id]]
      st_hosts = Array.new      #Array to hold host/datastore relationship that will be sorted and displayed under each storage node
      st.hosts.each do |h|
        # ems_name = ems_hash[h.ems_id]
        #         cname = "#{ems_name != nil ? "#{ems_name} : " : ""}" +
        #                 (h.parent_datacenter != nil ? "#{h.parent_datacenter.name} : " : "") +
        #                 (h.ems_cluster != nil ? "#{h.ems_cluster.name} : " : "") +
        #                 "#{h.name}"
        cname = h.name
        st_hosts.push({:name=>cname})
      end

      st_hosts.sort{|a,b| a[:name].downcase<=>b[:name].downcase}.each do |h|
        temp = Hash.new
        temp[:key] = h[:name]
        temp[:title] = h[:name]
        temp[:tooltip] = h[:name]
        temp[:style] = "cursor:default"      # No cursor pointer
        temp[:hideCheckbox] = true
        temp[:icon] = "host.png"
        children.push(temp)
      end

      ds_node[:children] = children unless children.empty?
      ds.push(ds_node)
    end

    @temp[:cu_datastore_tree] = ds.to_json # Add ems node array to root of tree
    session[:tree] = "cu_datastore"
    session[:ds_tree_name] = "cu_datastore_tree"
  end

  def process_form_vars_for_non_clustered(node_type)
    if node_type[1].to_i == 0     # dont add if non-clustered node was checked/unchecked
      if params[:check] == "1"
        @edit[:new][:non_cluster_host_enabled].each do |h|
          @edit[:new][:non_cluster_host_enabled][h[0]] = true
        end
      else
        @edit[:new][:non_cluster_host_enabled].each do |h|
          @edit[:new][:non_cluster_host_enabled][h[0]] = false
        end
      end
    else
      if params[:check] == "1"
        @edit[:new][:non_cluster_host_enabled][node_type[1].to_s] = true
      else
        @edit[:new][:non_cluster_host_enabled].each do |h|
          if h[0].to_s == node_type[1].to_s
            @edit[:new][:non_cluster_host_enabled][node_type[1].to_s] = false
          end
        end
      end
    end
  end

end
