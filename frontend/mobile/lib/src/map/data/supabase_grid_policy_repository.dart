import '../domain/grid_policy_repository.dart';
import '../domain/grid_policy.dart';
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
    final Object? response = await client.rpc(
      'get_grid_lock_snapshot',
      params: {'p_area_id': areaId},
    );
    return parseGridPolicySnapshot(response);
  }
}
