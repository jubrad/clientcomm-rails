require 'singleton'
require 'erb'

MessageInfo = Struct.new(:sid, :status)

class SMSService
  include AnalyticsHelper
  include Singleton

  class NumberNotFound < StandardError; end

  def initialize
    token = Rails.configuration.x.twilio.auth_token
    sid = Rails.configuration.x.twilio.account_sid
    @client = Twilio::REST::Client.new sid, token
  end

  def status_lookup(message:)
    message_lookup(twilio_sid: message.twilio_sid).status
  end

  def message_lookup(twilio_sid:)
    @client.api.account.messages(twilio_sid).fetch
  end

  def send_message(args)
    # send the message via Twilio
    response = @client.api.account.messages.create(args)

    MessageInfo.new(response.sid, response.status)
  end

  def redact_message(message:)
    Rails.logger.tagged('redact message') { Rails.logger.warn "redacting #{message.id}" }
    twilio_message = @client.api.account.messages(message.twilio_sid).fetch
    twilio_message.update(body: '')

    Rails.logger.tagged('redact message') { Rails.logger.warn "deleting #{twilio_message.num_media} media items from message #{message.id}" }
    twilio_message.media.list.each(&:delete) if twilio_message.num_media != '0'

    true
  rescue Twilio::REST::RestError => e
    raise e unless [20009, 20404].include? e.code
    false
  end

  def number_lookup(phone_number:)
    @client.lookups.v1.phone_numbers(ERB::Util.url_encode(phone_number)).fetch.phone_number
  rescue Twilio::REST::RestError => e
    if e.code == 20404
      raise NumberNotFound
    else
      raise e
    end
  end

  def twilio_params(twilio_message:)
    params = {
      From: twilio_message.from,
      To: twilio_message.to,
      SmsSid: twilio_message.sid,
      SmsStatus: twilio_message.status,
      Body: twilio_message.body,
      NumMedia: twilio_message.num_media
    }

    if twilio_message.num_media.to_i.positive?
      media_list = twilio_message.media.list
      twilio_message.num_media.to_i.times.each do |i|
        params["MediaUrl#{i}"] = "https://api.twilio.com#{media_list[i].uri.gsub(/\.json$/, '')}"
      end
    end

    params.with_indifferent_access
  end
end
