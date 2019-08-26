Noosfero::Application.configure do
  # Settings specified here will take precedence over those in config/application.rb

  # In the development environment your application's code is reloaded on
  # every request.  This slows down response time but is perfect for development
  # since you don't have to restart the webserver when you make code changes.
  config.cache_classes = false

  config.eager_load = true

  # Show full error reports and disable caching
  config.action_controller.perform_caching             = false

  # Don't care if the mailer can't send
  config.action_mailer.raise_delivery_errors = false

  # Print deprecation notices to the Rails logger
  config.active_support.deprecation = :log

  # Only use best-standards-support built into browsers
  config.action_dispatch.best_standards_support = :builtin

  # Raise exception on mass assignment protection for Active Record models
  config.active_record.mass_assignment_sanitizer = :strict

  # Do not compress assets
  config.assets.compress = false
  config.assets.digest = false
  # we have a lot of assets
  config.assets.debug = false

  config.consider_all_requests_local = true

  # send emails to /tmp/mails
  config.action_mailer.delivery_method = :file

  # Configuration Amazon Send Mail from SMTP
  #config.action_mailer.delivery_method = :smtp
  #config.action_mailer.default_options = {from: 'email@domain.com'}
  #config.action_mailer.smtp_settings = {
        #address:              'email-smtp.us-east-1.amazonaws.com',
        #port:                 587,
        #domain:               'yourdomain.com',
        #user_name:            'username',
        #password:             'password',
        #authentication:       'plain',
        #openssl_verify_mode: OpenSSL::SSL::VERIFY_NONE,
        #enable_starttls_auto: true }

end