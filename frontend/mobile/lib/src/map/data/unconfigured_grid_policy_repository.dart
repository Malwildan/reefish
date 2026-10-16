import '../domain/grid_policy_repository.dart';

class UnconfiguredGridPolicyRepository implements GridPolicyRepository {
  const UnconfiguredGridPolicyRepository();

  @override
  Future<Never> fetchSnapshot() async {
    throw StateError('Grid policy service is not configured');
  }
}
