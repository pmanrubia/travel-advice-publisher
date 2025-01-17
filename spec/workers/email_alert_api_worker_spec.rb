require "spec_helper"
require "sidekiq/testing"
require "gds_api/test_helpers/email_alert_api"

RSpec.describe EmailAlertApiWorker, :perform do
  include GdsApi::TestHelpers::EmailAlertApi

  let(:payload) do
    { "example" => "payload" }
  end

  before do
    stub_any_email_alert_api_call.with(body: payload.to_json)
    Sidekiq::RetrySet.new.clear
  end

  it "sends an alert to the email-alert-api" do
    described_class.new.perform(payload)
    assert_email_alert_sent(payload)
  end

  context "when send_email_alerts is disabled" do
    before do
      expect(Rails.application.config).to receive(:send_email_alerts)
        .and_return(false)
    end

    it "does not send an alert" do
      expect(TravelAdvicePublisher.email_alert_api).not_to receive(:send_alert)
      described_class.new.perform(payload)
    end
  end

  context "when a request to the email-alert-api fails" do
    before do
      stub_any_email_alert_api_call.to_timeout
    end

    it "does not raise an error to safeguard against duplicate emails being sent" do
      expect {
        described_class.new.perform(payload)
      }.not_to raise_error

      expect(Sidekiq::RetrySet.new.size).to be_zero
    end

    it "sends a helpful message to Errbit so that we can diagnose the problem" do
      expect(Airbrake).to receive(:notify_or_ignore) do |error|
        expect(error.message).to match(/=== Failed request details ===/)
      end

      described_class.new.perform(payload)
    end
  end
end
