# frozen_string_literal: true

module AutohandSDK
  # Original CLI method and JSON parameters, including future payload shapes.
  WireNotification = Data.define(:notification_method, :params)
end
