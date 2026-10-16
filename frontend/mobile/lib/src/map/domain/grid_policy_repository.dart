import 'grid_policy.dart';

abstract interface class GridPolicyRepository {
  Future<GridPolicySnapshot> fetchSnapshot();
}
