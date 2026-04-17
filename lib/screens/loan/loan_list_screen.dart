import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/status_chip.dart';
import '../../providers/app_providers.dart';
import 'loan_detail_screen.dart';

class LoanListScreen extends ConsumerWidget {
  const LoanListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loansAsync = ref.watch(loansProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Danh sách khoản vay')),
      body: loansAsync.when(
        data: (loans) {
          if (loans.isEmpty) {
            return const Center(child: Text('Chưa có khoản vay nào.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: loans.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final loan = loans[index];
              return Card(
                child: ListTile(
                  title: Text(AppFormatters.currency(loan.principal)),
                  subtitle: Text(
                    'Trả ${AppFormatters.currency(loan.monthlyInstallment)}/tháng',
                  ),
                  trailing: StatusChip(status: loan.status),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LoanDetailScreen(loan: loan),
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
