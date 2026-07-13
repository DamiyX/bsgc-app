const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
admin.initializeApp();

exports.sendPushNotification = onDocumentCreated(
  "groups/{groupId}/messages/{messageId}",
  async (event) => {
    const snap = event.data;
    const messageData = snap.data();
    const groupId = event.params.groupId;

    // We only send notifications for new messages
    if (!messageData || !messageData.senderId) return;

    const senderId = messageData.senderId;
    const senderName = messageData.senderName || "Believer";
    const parts = messageData.parts || [];

    // Extract preview text
    let notificationBody = "Sent a message";
    if (parts.length > 0) {
      const firstPart = parts[0];
      if (firstPart.type === "text" && firstPart.content) {
        notificationBody = firstPart.content.length > 50
          ? firstPart.content.substring(0, 50) + "..."
          : firstPart.content;
      } else if (firstPart.type === "voice") {
        notificationBody = "🎤 Voice note";
      } else if (firstPart.type === "image") {
        notificationBody = "📷 Image";
      }
    }

    try {
      // Get the group document to find members
      const groupDoc = await admin.firestore().collection("groups").doc(groupId).get();
      if (!groupDoc.exists) return;
      
      const groupData = groupDoc.data();
      const groupName = groupData.name || "Study Group";
      const members = groupData.members || [];

      // Fetch FCM tokens for all members EXCEPT the sender
      const tokens = [];
      for (const memberId of members) {
        if (memberId !== senderId) {
          const userDoc = await admin.firestore().collection("users").doc(memberId).get();
          if (userDoc.exists) {
            const fcmToken = userDoc.data().fcmToken;
            if (fcmToken) {
              tokens.push(fcmToken);
            }
          }
        }
      }

      if (tokens.length === 0) {
        console.log("No valid FCM tokens found for other group members.");
        return;
      }

      // Create the modern multicast message payload
      const message = {
        notification: {
          title: `${senderName} in ${groupName}`,
          body: notificationBody,
        },
        data: {
          groupId: groupId,
        },
        tokens: tokens,
      };

      // Send the notifications
      const response = await admin.messaging().sendEachForMulticast(message);
      console.log(`Successfully sent ${response.successCount} messages. Failed: ${response.failureCount}`);
      
    } catch (error) {
      console.error("Error sending push notification:", error);
    }
  });
