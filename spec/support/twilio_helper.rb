module TwilioHelper
  def twilio_post_sms(tw_params = twilio_new_message_params, use_correct_signature = true)
    post_path = '/incoming/sms'
    post_sig = use_correct_signature ? correct_signature(tw_params, post_path) : nil
    twilio_post tw_params, post_sig, post_path
  end

  def twilio_post_sms_status(tw_params = twilio_status_update_params, use_correct_signature = true, tw_headers = {})
    post_path = '/incoming/sms/status'
    post_sig = use_correct_signature ? correct_signature(tw_params, post_path) : nil
    twilio_post tw_params, post_sig, post_path, tw_headers
  end

  def twilio_post_voice(tw_params = {}, use_correct_signature = true)
    tw_params = twilio_status_update_params.merge(tw_params)
    post_path = '/incoming/voice'
    post_sig = use_correct_signature ? correct_signature(tw_params, post_path) : nil
    twilio_post tw_params, post_sig, post_path
  end

  def twilio_clear_after
    if defined?(page) && !Capybara.current_session.server
      page.driver.header post_header_name, nil
    end
  end

  def twilio_rest_error(error_code, message="", resp_dict={})
    # TODO decouple errors with name lookup to code
    # https://assets.cdn.prod.twilio.com/documents/twilio-error-codes.json
    Twilio::REST::RestError.new(message, Twilio::Response.new(error_code,resp_dict.to_json))
  end

  def post_header_name
    'X-Twilio-Signature'
  end

  def twilio_message_text
    'This is a test message.'
  end

  def twilio_new_message_params(
    from_number: '+12425551212',
    to_number: '+12435551212',
    sms_sid: SecureRandom.hex(17),
    msg_txt: twilio_message_text
  )
    HashWithIndifferentAccess.new(
      'ToCountry' => 'US',
      'ToState' => 'CA',
      'SmsMessageSid' => sms_sid,
      'NumMedia' => '0',
      'ToCity' => '',
      'FromZip' => '94005',
      'SmsSid' => sms_sid,
      'FromState' => 'CA',
      'SmsStatus' => 'received',
      'FromCity' => 'SAN FRANCISCO',
      'Body' => msg_txt,
      'FromCountry' => 'US',
      'To' => to_number,
      'ToZip' => '',
      'AddOns' => '{"status":"successful","message":null,"code":null,"results":{}}',
      'NumSegments' => '1',
      'MessageSid' => sms_sid,
      'AccountSid' => '077541f41cce52ea6c4944fa6823a4a277',
      'From' => from_number,
      'ApiVersion' => '2010-04-01',
      'controller' => 'twilio',
      'action' => 'incoming_sms'
    )
  end

  def twilio_status_update_params(
    from_number: '+12425551212',
    sms_sid: SecureRandom.hex(17),
    sms_status: 'delivered',
    to_number: '+12435551212'
  )
    {
      'SmsSid' => sms_sid,
      'SmsStatus' => sms_status,
      'MessageStatus' => sms_status,
      'To' => to_number,
      'MessageSid' => sms_sid,
      'AccountSid' => '077541f41cce52ea6c4944fa6823a4a277',
      'From' => from_number,
      'ApiVersion' => '2010-04-01',
      'controller' => 'twilio',
      'action' => 'incoming_sms_status'
    }
  end

  def twilio_stub_normalization(client:, abnormal_number:, normal_number:)
    phone_numbers = double('phone_numbers')

    allow(client).to receive(:phone_numbers).with(ERB::Util.url_encode(abnormal_number)).and_return(phone_numbers)
    allow(phone_numbers).to receive(:fetch)
      .with(no_args)
      .and_return(double('phone_number', phone_number: normal_number))
  end

  private

  def twilio_post(tw_params, post_sig, post_url, tw_headers = {})
    if Capybara.current_session.server
      conn = Faraday.new(myhost.to_s)
      conn.post do |req|
        req.url post_url
        req.headers[post_header_name] = post_sig
        req.headers.merge! tw_headers
        req.body = tw_params
      end
    elsif defined?(page)
      page.driver.header post_header_name, post_sig
      page.driver.post post_url, tw_params
    else
      post post_url, params: tw_params, headers: { post_header_name => post_sig }
    end
  end

  def myhost
    if Capybara.current_session.server
      return "http://#{Capybara.current_session.server.host}:#{Capybara.current_session.server.port}"
    end
    Capybara.current_host || Capybara.default_host
  end

  def correct_signature(tw_params = twilio_new_message_params, post_path = '')
    Twilio::Security::RequestValidator
      .new(Rails.configuration.x.twilio.auth_token)
      .build_signature_for("#{myhost}#{post_path}", tw_params)
  end
end
