GDS::SSO.config do |config|
  config.user_model   = 'User'
  config.oauth_id     = 'abcdefghjasndjkasndtraveladvicepublisher'
  config.oauth_secret = 'secret'
  config.oauth_root_url = Plek.current.find("signon")
end
