import 'package:cloud_functions/cloud_functions.dart';

class AccountService {
  final FirebaseFunctions _functions;

  AccountService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  Future<void> deleteCurrentAccount() async {
    try {
      await _functions.httpsCallable('deleteCurrentAccount').call();
    } on FirebaseFunctionsException catch (error) {
      throw AccountDeletionException(
        error.message ?? 'Your account could not be deleted.',
      );
    }
  }
}

class AccountDeletionException implements Exception {
  final String message;

  const AccountDeletionException(this.message);

  @override
  String toString() => message;
}
