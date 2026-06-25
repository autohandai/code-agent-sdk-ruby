# frozen_string_literal: true

module AutohandSDK
  module HookEvents
    SESSION_START = "session-start"
    SESSION_END = "session-end"
    PRE_CLEAR = "pre-clear"
    PRE_PROMPT = "pre-prompt"
    PRE_TOOL = "pre-tool"
    POST_TOOL = "post-tool"
    FILE_MODIFIED = "file-modified"
    STOP = "stop"
    POST_RESPONSE = "post-response"
    SUBAGENT_STOP = "subagent-stop"
    PERMISSION_REQUEST = "permission-request"
    NOTIFICATION = "notification"
    SESSION_ERROR = "session-error"

    AUTOMODE_START = "automode:start"
    AUTOMODE_ITERATION = "automode:iteration"
    AUTOMODE_CHECKPOINT = "automode:checkpoint"
    AUTOMODE_PAUSE = "automode:pause"
    AUTOMODE_RESUME = "automode:resume"
    AUTOMODE_CANCEL = "automode:cancel"
    AUTOMODE_COMPLETE = "automode:complete"
    AUTOMODE_ERROR = "automode:error"

    PRE_LEARN = "pre-learn"
    POST_LEARN = "post-learn"

    TEAM_CREATED = "team-created"
    TEAMMATE_SPAWNED = "teammate-spawned"
    TEAMMATE_IDLE = "teammate-idle"
    TASK_ASSIGNED = "task-assigned"
    TASK_COMPLETED = "task-completed"
    TEAM_SHUTDOWN = "team-shutdown"

    REVIEW_START = "review:start"
    REVIEW_END = "review:end"
    REVIEW_PAUSED = "review:paused"
    REVIEW_FAILED = "review:failed"
    REVIEW_COMPLETED = "review:completed"

    MODE_CHANGE = "mode-change"
    CONTEXT_COMPACT = "context:compact"
    CONTEXT_OVERFLOW = "context:overflow"
    CONTEXT_WARNING = "context:warning"
    CONTEXT_CRITICAL = "context:critical"

    ALL = [
      SESSION_START,
      SESSION_END,
      PRE_CLEAR,
      PRE_PROMPT,
      PRE_TOOL,
      POST_TOOL,
      FILE_MODIFIED,
      STOP,
      POST_RESPONSE,
      SUBAGENT_STOP,
      PERMISSION_REQUEST,
      NOTIFICATION,
      SESSION_ERROR,
      AUTOMODE_START,
      AUTOMODE_ITERATION,
      AUTOMODE_CHECKPOINT,
      AUTOMODE_PAUSE,
      AUTOMODE_RESUME,
      AUTOMODE_CANCEL,
      AUTOMODE_COMPLETE,
      AUTOMODE_ERROR,
      PRE_LEARN,
      POST_LEARN,
      TEAM_CREATED,
      TEAMMATE_SPAWNED,
      TEAMMATE_IDLE,
      TASK_ASSIGNED,
      TASK_COMPLETED,
      TEAM_SHUTDOWN,
      REVIEW_START,
      REVIEW_END,
      REVIEW_PAUSED,
      REVIEW_FAILED,
      REVIEW_COMPLETED,
      MODE_CHANGE,
      CONTEXT_COMPACT,
      CONTEXT_OVERFLOW,
      CONTEXT_WARNING,
      CONTEXT_CRITICAL
    ].freeze
  end
end
