import os

def patch_file(filepath, old_str, new_str):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    if old_str in content:
        content = content.replace(old_str, new_str)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Patched {filepath}")
    else:
        print(f"Pattern not found in {filepath}")

# chat_service.dart
patch_file("lib/services/chat_service.dart",
           "    docRef.set(data);",
           "    try {\n      await docRef.set(data).timeout(const Duration(seconds: 2));\n    } on TimeoutException {\n      // Offline or slow connection. Local cache will sync later.\n    }")

# insight_service.dart (multiple methods)
insight_methods = [
    ("    _firestore.collection('insights').doc(insight.id).set(insight.toMap());", 
     "    try {\n      await _firestore.collection('insights').doc(insight.id).set(insight.toMap()).timeout(const Duration(seconds: 2));\n    } on TimeoutException {\n      // Offline sync fallback\n    }"),
    ("    _firestore.collection('insights').doc(insightId).delete();",
     "    try {\n      await _firestore.collection('insights').doc(insightId).delete().timeout(const Duration(seconds: 2));\n    } on TimeoutException {\n      // Offline sync fallback\n    }"),
    ("    _firestore.collection('insights').doc(insightId).update({",
     "    try {\n      await _firestore.collection('insights').doc(insightId).update({"),
    ("      'seenBy': FieldValue.arrayUnion([userId])\n    });",
     "      'seenBy': FieldValue.arrayUnion([userId])\n    }).timeout(const Duration(seconds: 2));\n    } on TimeoutException {\n      // Offline sync fallback\n    }"),
    ("    _firestore\n        .collection('insights')",
     "    try {\n      await _firestore\n        .collection('insights')"),
    ("        .doc(comment.id)\n        .set(comment.toMap());",
     "        .doc(comment.id)\n        .set(comment.toMap())\n        .timeout(const Duration(seconds: 2));\n    } on TimeoutException {\n      // Offline sync fallback\n    }"),
    ("        .collection('comments')\n        .doc(commentId)",
     "        .collection('comments')\n        .doc(commentId)"),
    ("        .update({'likes': FieldValue.increment(1)});",
     "        .update({'likes': FieldValue.increment(1)})\n        .timeout(const Duration(seconds: 2));\n    } on TimeoutException {\n      // Offline sync fallback\n    }"),
    ("        .update({'likes': FieldValue.increment(-1)});",
     "        .update({'likes': FieldValue.increment(-1)})\n        .timeout(const Duration(seconds: 2));\n    } on TimeoutException {\n      // Offline sync fallback\n    }"),
    ("    _firestore\n        .collection('users')",
     "    try {\n      await _firestore\n        .collection('users')"),
    ("        .collection('saved_insights')\n        .doc(insight.id)\n        .set(insight.toMap());",
     "        .collection('saved_insights')\n        .doc(insight.id)\n        .set(insight.toMap())\n        .timeout(const Duration(seconds: 2));\n    } on TimeoutException {\n      // Offline sync fallback\n    }"),
    ("        .collection('saved_insights')\n        .doc(insightId)\n        .delete();",
     "        .collection('saved_insights')\n        .doc(insightId)\n        .delete()\n        .timeout(const Duration(seconds: 2));\n    } on TimeoutException {\n      // Offline sync fallback\n    }")
]

for old, new in insight_methods:
    patch_file("lib/services/insight_service.dart", old, new)

# Need to add import 'dart:async'; to the top of the files if not present
def add_import(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    if "import 'dart:async';" not in content:
        content = "import 'dart:async';\n" + content
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Added dart:async to {filepath}")

add_import("lib/services/chat_service.dart")
add_import("lib/services/insight_service.dart")

