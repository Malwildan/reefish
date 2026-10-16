import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../map/data/local_departure_repository.dart';
import '../map/data/local_fishing_point_repository.dart';
import '../map/data/supabase_grid_policy_repository.dart';
import '../map/data/unconfigured_grid_policy_repository.dart';
import '../map/domain/departure_repository.dart';
import '../map/domain/fishing_point_repository.dart';
import '../map/domain/grid_policy_repository.dart';
import '../map/presentation/departure_screen.dart';

/// Composition boundary: a preview may inject explicit example policies,
/// while normal app entry always reads the configured backend.
class DepartureEntry extends StatefulWidget {
  const DepartureEntry({
    this.gridPolicyRepository,
    this.departureRepository,
    this.fishingPointRepository,
    this.onBack,
    super.key,
  });

  final GridPolicyRepository? gridPolicyRepository;
  final DepartureRepository? departureRepository;
  final FishingPointRepository? fishingPointRepository;
  final VoidCallback? onBack;

  @override
  State<DepartureEntry> createState() => _DepartureEntryState();
}

class _DepartureEntryState extends State<DepartureEntry> {
  late Future<({DepartureRepository departure, FishingPointRepository fishing})>
  _repositories;
  late final GridPolicyRepository _policies;

  @override
  void initState() {
    super.initState();
    SupabaseClient? client;
    try {
      client = Supabase.instance.client;
    } catch (_) {
      // App can run without Supabase configuration, with unknown grid status.
    }
    _policies =
        widget.gridPolicyRepository ??
        (client == null
            ? const UnconfiguredGridPolicyRepository()
            : SupabaseGridPolicyRepository(client: client));
    final owner = client?.auth.currentUser?.id ?? 'preview-anonymous';
    _repositories = _createRepositories(owner);
  }

  Future<({DepartureRepository departure, FishingPointRepository fishing})>
  _createRepositories(String owner) async {
    final preferences = await SharedPreferences.getInstance();
    return (
      departure:
          widget.departureRepository ??
          LocalDepartureRepository(
            preferences: preferences,
            storageKey: 'reefish.departure-point.v1.$owner',
          ),
      fishing:
          widget.fishingPointRepository ??
          LocalFishingPointRepository(preferences: preferences, ownerId: owner),
    );
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<
        ({DepartureRepository departure, FishingPointRepository fishing})
      >(
        future: _repositories,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Penyimpanan perangkat belum tersedia.'),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: widget.onBack,
                          child: const Text('Kembali'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          final repository = snapshot.data;
          if (repository == null) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return DepartureScreen(
            gridPolicyRepository: _policies,
            departureRepository: repository.departure,
            fishingPointRepository: repository.fishing,
            onBack: widget.onBack,
          );
        },
      );
}
