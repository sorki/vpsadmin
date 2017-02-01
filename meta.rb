VpsAdmin::API::Plugin.register(:webui) do
  name 'Web UI support'
  description 'Support for Web UI specific API endpoints'
  version '0.1.0'
  author 'Jakub Skokan'
  email 'jakub.skokan@vpsfree.cz'
  components :api

  config do
    SysConfig.register :webui, :base_url, String
    SysConfig.register :webui, :document_title, String
    SysConfig.register :webui, :noticeboard, Text
    SysConfig.register :webui, :index_info_box_title, String
    SysConfig.register :webui, :index_info_box_content, Text
  end
end
