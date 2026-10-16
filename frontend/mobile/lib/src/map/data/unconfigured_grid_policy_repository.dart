import '../domain/grid_policy_repository.dart';
import '../domain/grid_policy_failure.dart';

class UnconfiguredGridPolicyRepository implements GridPolicyRepository {
  const UnconfiguredGridPolicyRepository();

  @override
  Future<Never> fetchSnapshot() async {
    throw const GridPolicyFailure(GridPolicyFailureCode.notConfigured);
  }
}
