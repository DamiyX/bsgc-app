import 'package:cloud_functions/cloud_functions.dart';

class AccountService {
  final FirebaseFunctions _functions;

  AccountService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  Future<AccountDeletionRequest> deleteCurrentAccount() async {
    try {
      final result = await _functions
          .httpsCallable('deleteCurrentAccount')
          .call<Map<String, dynamic>>();
      final data = result.data;
      return AccountDeletionRequest(
        status: data['status']?.toString() ?? 'queued',
        phase: data['phase']?.toString() ?? 'preflight',
      );
    } on FirebaseFunctionsException catch (error) {
      throw AccountDeletionException(
        error.message ?? 'Your account could not be deleted.',
      );
    }
  }
}

class AccountDeletionRequest {
  final String status;
  final String phase;

  const AccountDeletionRequest({required this.status, required this.phase});
}

class AccountDeletionException implements Exception {
  final String message;

  const AccountDeletionException(this.message);

  @override
  String toString() => message;
}
