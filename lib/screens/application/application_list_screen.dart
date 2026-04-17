import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/status_chip.dart';
import '../../providers/app_providers.dart';
import 'application_detail_screen.dart';

class ApplicationListScreen extends ConsumerWidget {
  const ApplicationListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final applicationsAsync = ref.watch(loanApplicationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Danh sách hồ sơ vay')),
      body: applicationsAsync.when(
        data: (applications) {
          if (applications.isEmpty) {
            return const Center(child: Text('Chưa có hồ sơ vay nào.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: applications.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final application = applications[index];
              return Card(
                child: ListTile(
                  title: Text(AppFormatters.currency(application.amount)),
                  subtitle: Text(
                    '${application.termMonths} tháng • ${AppFormatters.dateTime(application.createdAt)}',
                  ),
                  trailing: StatusChip(status: application.status),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ApplicationDetailScreen(
                          application: application,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Lỗi: $error')),
      ),
    );
  }
}
