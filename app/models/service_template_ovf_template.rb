class ServiceTemplateOvfTemplate < ServiceTemplateGeneric
  def self.default_provisioning_entry_point(_service_type)
    '/Service/Generic/StateMachines/GenericLifecycle/provision'
  end

  # create ServiceTemplate and supporting ServiceResources and ResourceActions
  # options
  #   :name
  #   :description
  #   :service_template_catalog_id
  #   :config_info
  #     :provision
  #       :dialog_id or :dialog
  #       :template_id or :template
  #
  def self.create_catalog_item(options, _auth_user)
    options = options.merge(:service_type => 'atomic', :prov_type => 'generic_ovf_template')
    config_info = validate_config_info(options[:config_info])
    enhanced_config = config_info.deep_merge(
      :provision => {
        :configuration_template => template_from_config_info(config_info)
      }
    )

    transaction do
      create_from_options(options).tap do |service_template|
        service_template.create_resource_actions(enhanced_config)
      end
    end
  end

  def self.validate_config_info(info)
    info[:provision][:fqname] ||= default_provisioning_entry_point(SERVICE_TYPE_ATOMIC) if info.key?(:provision)
    info[:reconfigure][:fqname] ||= default_reconfiguration_entry_point if info.key?(:reconfigure)
    info[:retirement][:fqname] ||= default_retirement_entry_point if info.key?(:retirement)

    # TODO: Add more validation for required fields
    info
  end
  private_class_method :validate_config_info

  def self.template_from_config_info(info)
    template_id = info[:provision][:template_id]
    template_id ? OrchestrationTemplate.find(template_id) : info[:provision][:template]
  end
  private_class_method :template_from_config_info

  def template
    @template ||= resource_actions.find_by(:action => "Provision").try(:configuration_template)
  end

  def manager
    @manager ||= template.try(:ext_management_system)
  end

  def update_catalog_item(options)
    config_info = validate_update_config_info(options)
    config_info[:provision][:configuration_template] ||= template_from_config_info(config_info) if config_info.key?(:provision)
    options[:config_info] = config_info

    super
  end

  private

  def template_from_config_info(info)
    self.class.send(:template_from_config_info, info)
  end

  def validate_update_config_info(options)
    opts = super
    self.class.send(:validate_config_info, opts)
  end

  def update_service_resources(_config_info, _auth_user = nil)
    # do nothing since no service resources for this template
  end

  def update_from_options(params)
    options[:config_info] = Hash[params[:config_info].collect { |k, v| [k, v.except(:configuration_template)] }]
    update!(params.except(:config_info))
  end
end
