"use strict";

const unicodeNoteBody = "🙏🏾 λόγος אור ".repeat(1500);

module.exports = {
  unicodeNoteBody,
  users: [
    {
      id: "legacy-user",
      data: {
        displayName: null,
        photoURL: 42,
        phone: "+2348000000000",
        onboardingComplete: "yes",
      },
    },
  ],
  groups: [
    {
      id: "legacy-group",
      data: {
        members: ["owner", "member", "member", null],
        name: null,
        description: 42,
        groupType: "Devotional",
        topic: "Grace",
        readingProgress: { owner: 2, member: "0.5", ghost: 0.2 },
        userCompletedChapters: { owner: [1, 1, "2"], ghost: [3] },
        unreadCounts: { owner: -1, member: 4.8, ghost: 3 },
        extensionCount: "2",
      },
    },
  ],
  notes: [
    {
      id: "unicode-note",
      uid: "legacy-user",
      data: { title: null, body: unicodeNoteBody, themeColor: null },
    },
    {
      id: "empty-note",
      uid: "legacy-user",
      data: { body: null },
    },
  ],
  messages: [
    {
      id: "legacy-text",
      groupId: "legacy-group",
      data: { authorUid: "owner", authorName: "Owner", content: "hello" },
    },
    {
      id: "legacy-managed-voice",
      groupId: "legacy-group",
      data: {
        senderId: "owner",
        senderName: "Owner",
        parts: [{
          type: "voice",
          content:
            "groups/legacy-group/messages/legacy-managed-voice/audio.m4a",
          assetId: "managed-asset",
          durationSeconds: 31,
          fileName: "audio.m4a",
          sizeBytes: 1024,
        }],
      },
    },
    {
      id: "legacy-https-image",
      groupId: "legacy-group",
      data: {
        userId: "owner",
        type: "image",
        content: "https://legacy.example/image.jpg",
      },
    },
  ],
  insights: [
    {
      id: "legacy-insight",
      data: {
        userId: "legacy-user",
        userName: "Legacy User",
        title: null,
        content: "A reflection",
        themeColor: "theme_3",
        seenBy: ["viewer", null],
        likedBy: "wrong-type",
      },
    },
  ],
  invites: [
    {
      id: "raw-legacy-token",
      collection: "group_invites",
      data: {
        group: "legacy-group",
        inviterId: "owner",
        maxUses: "3",
        uses: 1,
      },
    },
  ],
};
