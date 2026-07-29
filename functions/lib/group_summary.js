const { messagePreview } = require("./contracts");

function groupSummaryFromMessage({
  messageId,
  message,
  canonicalSenderName,
  fallbackTimestamp,
}) {
  return {
    lastMessageId: messageId,
    lastMessageTime: message.timestamp ?? fallbackTimestamp,
    lastMessageText: messagePreview(message.parts),
    lastMessageSenderName: canonicalSenderName,
    lastMessageSenderId: message.senderId,
  };
}

function shouldReconcileGroupSummary({
  lastMessageId,
  changedMessageId,
  latestMessageId,
}) {
  return !lastMessageId ||
    lastMessageId === changedMessageId ||
    !latestMessageId ||
    lastMessageId !== latestMessageId;
}

module.exports = {
  groupSummaryFromMessage,
  shouldReconcileGroupSummary,
};
