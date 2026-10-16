import '../domain/grid_policy_repository.dart';
import '../domain/grid_policy.dart';
import '../domain/grid_policy_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'grid_policy_snapshot_parser.dart';

class SupabaseGridPolicyRepository implements GridPolicyRepository {
  const SupabaseGridPolicyRepository({
    required this.client,
    this.areaId = 'east-java-pilot',
  });

  final SupabaseClient client;
  final String areaId;

  @override
  Future<GridPolicySnapshot> fetchSnapshot() async {
    if (client.auth.currentSession == null) {
      throw const GridPolicyFailure(
        GridPolicyFailureCode.authenticationRequired,
      );
    }

    try {
      final Object? response = await client.rpc(
        'get_grid_lock_snapshot',
        params: {'p_area_id': areaId},
      );
      try {
        return parseGridPolicySnapshot(response);
      } on GridPolicyFormatException {
        throw const GridPolicyFailure(GridPolicyFailureCode.invalidResponse);
      }
    } on GridPolicyFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw GridPolicyFailure(_failureCodeForPostgrest(error));
    } catch (_) {
      throw const GridPolicyFailure(GridPolicyFailureCode.unavailable);
    }
  }

  GridPolicyFailureCode _failureCodeForPostgrest(PostgrestException error) {
    // PostgREST's JWT validation error is PGRST301. Some proxies omit its
    // JSON error code and leave the HTTP status as the exception code.
    if (error.code == 'PGRST301' || error.code == '401') {
      return GridPolicyFailureCode.authenticationRequired;
    }
    if (error.code == '42501') {
      return GridPolicyFailureCode.permissionDenied;
    }
    return GridPolicyFailureCode.unavailable;
  }
}
