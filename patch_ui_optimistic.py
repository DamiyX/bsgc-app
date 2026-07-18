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

def add_import(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    if "import 'dart:async';" not in content:
        content = "import 'dart:async';\n" + content
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Added dart:async to {filepath}")

# onboarding_screen.dart
add_import("lib/screens/onboarding_screen.dart")
patch_file("lib/screens/onboarding_screen.dart",
           "FirebaseFirestore.instance.collection('users').doc(user.uid).set",
           "try { await FirebaseFirestore.instance.collection('users').doc(user.uid).set")
patch_file("lib/screens/onboarding_screen.dart",
           "({'phoneNumber': phone});",
           "({'phoneNumber': phone}).timeout(const Duration(seconds: 2)); } on TimeoutException {}")

patch_file("lib/screens/onboarding_screen.dart",
           "FirebaseFirestore.instance.collection('users').doc(uid).update",
           "try { await FirebaseFirestore.instance.collection('users').doc(uid).update")
patch_file("lib/screens/onboarding_screen.dart",
           "({'magicLinkSent': true});",
           "({'magicLinkSent': true}).timeout(const Duration(seconds: 2)); } on TimeoutException {}")

# edit_profile_screen.dart
add_import("lib/screens/edit_profile_screen.dart")
patch_file("lib/screens/edit_profile_screen.dart",
           "FirebaseFirestore.instance.collection('users').doc(user.uid).update",
           "try { await FirebaseFirestore.instance.collection('users').doc(user.uid).update")
patch_file("lib/screens/edit_profile_screen.dart",
           "      'bio': bio,\n    });",
           "      'bio': bio,\n    }).timeout(const Duration(seconds: 2)); } on TimeoutException {}")
patch_file("lib/screens/edit_profile_screen.dart",
           "FirebaseFirestore.instance.collection('users').doc(widget.user.uid).update({'photoURL': downloadUrl});",
           "try { await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).update({'photoURL': downloadUrl}).timeout(const Duration(seconds: 2)); } on TimeoutException {}")

# inviter_selection_screen.dart
add_import("lib/screens/inviter_selection_screen.dart")
patch_file("lib/screens/inviter_selection_screen.dart",
           "FirebaseFirestore.instance.collection('users').doc(user.uid).update({'referredBy': inviterId});",
           "try { await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'referredBy': inviterId}).timeout(const Duration(seconds: 2)); } on TimeoutException {}")

# main_hall_screen.dart
add_import("lib/screens/main_hall_screen.dart")
patch_file("lib/screens/main_hall_screen.dart",
           "FirebaseFirestore.instance.collection('users').doc(user.uid).update({'photoURL': downloadUrl});",
           "try { await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'photoURL': downloadUrl}).timeout(const Duration(seconds: 2)); } on TimeoutException {}")

