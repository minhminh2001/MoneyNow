import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../models/loan.dart';
import '../../models/loan_application.dart';
import '../../providers/app_providers.dart';
import '../../repositories/admin_repository.dart';

class AdminCustomersScreen extends ConsumerStatefulWidget {
  const AdminCustomersScreen({super.key});

  @override
  ConsumerState<AdminCustomersScreen> createState() =>
      _AdminCustomersScreenState();
}

class _AdminCustomersScreenState extends ConsumerState<AdminCustomersScreen> {
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  List<_CustomerAdminRecord> _records = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dashboard =
          await ref.read(adminRepositoryProvider).fetchDashboard();
      if (!mounted) return;
      setState(() {
        _records = _buildRecords(dashboard);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  List<_CustomerAdminRecord> _buildRecords(AdminDashboardData dashboard) {
    final applicationsByUid = <String, List<LoanApplication>>{};
    final loansByUid = <String, List<Loan>>{};

    for (final application in dashboard.applications) {
      applicationsByUid.putIfAbsent(application.uid, () => []).add(application);
    }
    for (final loan in dashboard.loans) {
      loansByUid.putIfAbsent(loan.uid, () => []).add(loan);
    }

    final records = <_CustomerAdminRecord>[];
    dashboard.userSummaries.forEach((uid, summary) {
      final role = (summary['role']?.toString().trim().toLowerCase() ?? '');
      if (role == 'admin') return;

      final applications = applicationsByUid[uid] ?? const [];
      final loans = loansByUid[uid] ?? const [];

      applications.sort((a, b) {
        final aTime = a.updatedAt?.millisecondsSinceEpoch ?? 0;
        final bTime = b.updatedAt?.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime);
      });
      loans.sort((a, b) {
        final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
        final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime);
      });

      final latestApplication =
          applications.isEmpty ? null : applications.first;
      final latestLoan = loans.isEmpty ? null : loans.first;

      records.add(
        _CustomerAdminRecord(
          uid: uid,
          fullName: summary['fullName']?.toString().trim().isNotEmpty == true
              ? summary['fullName'].toString().trim()
              : 'Khách hàng $uid',
          phone: summary['phone']?.toString().trim() ?? '',
          email: summary['email']?.toString().trim() ?? '',
          kycStatus: summary['kycStatus']?.toString().trim() ?? 'pending',
          applicationCount: applications.length,
          loanCount: loans.length,
          latestApplication: latestApplication,
          latestLoan: latestLoan,
        ),
      );
    });

    records.sort((a, b) {
      final aTime = a.latestLoan?.createdAt?.millisecondsSinceEpoch ??
          a.latestApplication?.updatedAt?.millisecondsSinceEpoch ??
          0;
      final bTime = b.latestLoan?.createdAt?.millisecondsSinceEpoch ??
          b.latestApplication?.updatedAt?.millisecondsSinceEpoch ??
          0;
      return bTime.compareTo(aTime);
    });

    return records;
  }

  List<_CustomerAdminRecord> get _filteredRecords {
    final search = _searchQuery.trim().toLowerCase();
    if (search.isEmpty) return _records;
    final searchablePhone = search.replaceAll(RegExp(r'[^\d]'), '');
    return _records.where((record) {
      final rawPhone = record.phone.replaceAll(RegExp(r'[^\d]'), '');
      return record.fullName.toLowerCase().contains(search) ||
          record.email.toLowerCase().contains(search) ||
          record.uid.toLowerCase().contains(search) ||
          (searchablePhone.isNotEmpty && rawPhone.contains(searchablePhone));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Không thể tải danh sách khách hàng: $_error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Tải lại'),
              ),
            ],
          ),
        ),
      );
    }

    final records = _filteredRecords;

    return RefreshIndicator(
      onRefresh: () async {
        _load();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _CustomerStatCard(
                label: 'Tổng khách hàng',
                value: '${_records.length}',
              ),
              _CustomerStatCard(
                label: 'Đã có hồ sơ vay',
                value:
                    '${_records.where((item) => item.applicationCount > 0).length}',
              ),
              _CustomerStatCard(
                label: 'Đang có khoản vay',
                value: '${_records.where((item) => item.loanCount > 0).length}',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Tìm theo tên, số điện thoại, email hoặc UID',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: records.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Chưa có khách hàng phù hợp với bộ lọc.'),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 18,
                        headingRowColor: const WidgetStatePropertyAll(
                          Color(0xFFF7FAFD),
                        ),
                        columns: const [
                          DataColumn(label: Text('Khách hàng')),
                          DataColumn(label: Text('Liên hệ')),
                          DataColumn(label: Text('KYC')),
                          DataColumn(label: Text('Hồ sơ vay gần nhất')),
                          DataColumn(label: Text('Khoản vay hiện tại')),
                          DataColumn(label: Text('Thống kê')),
                        ],
                        rows: records
                            .map(
                              (record) => DataRow(
                                cells: [
                                  DataCell(
                                    Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(record.fullName),
                                        Text(
                                          record.uid,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: const Color(0xFF6B7A90),
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  DataCell(
                                    Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          record.phone.isEmpty
                                              ? '-'
                                              : record.phone,
                                        ),
                                        Text(
                                          record.email.isEmpty
                                              ? '-'
                                              : record.email,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: const Color(0xFF6B7A90),
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  DataCell(_KycBadge(status: record.kycStatus)),
                                  DataCell(
                                    _LoanApplicationCell(
                                      application: record.latestApplication,
                                    ),
                                  ),
                                  DataCell(
                                    _LoanCell(
                                      loan: record.latestLoan,
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      '${record.applicationCount} hồ sơ\n${record.loanCount} khoản vay',
                                    ),
                                  ),
                                ],
                              ),
                            )
                            .toList(),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerAdminRecord {
  const _CustomerAdminRecord({
    required this.uid,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.kycStatus,
    required this.applicationCount,
    required this.loanCount,
    required this.latestApplication,
    required this.latestLoan,
  });

  final String uid;
  final String fullName;
  final String phone;
  final String email;
  final String kycStatus;
  final int applicationCount;
  final int loanCount;
  final LoanApplication? latestApplication;
  final Loan? latestLoan;
}

class _CustomerStatCard extends StatelessWidget {
  const _CustomerStatCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF6B7A90),
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: const Color(0xFF12343B),
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KycBadge extends StatelessWidget {
  const _KycBadge({
    required this.status,
  });

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().toLowerCase();
    final label = _labelFor(normalized);
    final color = _backgroundFor(normalized);
    final textColor = _textColorFor(normalized);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  String _labelFor(String normalized) {
    switch (normalized) {
      case 'verified':
        return 'Đã xác minh';
      case 'submitted':
        return 'Đã nộp';
      case 'pending':
        return 'Chưa đủ';
      default:
        return normalized.isEmpty ? 'Chưa rõ' : normalized;
    }
  }

  Color _backgroundFor(String normalized) {
    switch (normalized) {
      case 'verified':
        return const Color(0xFFE7F6EA);
      case 'submitted':
        return const Color(0xFFFFF1E5);
      case 'pending':
      default:
        return const Color(0xFFF0F4F8);
    }
  }

  Color _textColorFor(String normalized) {
    switch (normalized) {
      case 'verified':
        return const Color(0xFF2E7D32);
      case 'submitted':
        return const Color(0xFFE46A11);
      case 'pending':
      default:
        return const Color(0xFF607287);
    }
  }
}

class _LoanApplicationCell extends StatelessWidget {
  const _LoanApplicationCell({
    required this.application,
  });

  final LoanApplication? application;

  @override
  Widget build(BuildContext context) {
    if (application == null) return const Text('-');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppFormatters.currency(application!.amount)),
        Text(
          '${application!.termWeeks} tuần • ${_applicationStatus(application!.status)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6B7A90),
              ),
        ),
      ],
    );
  }

  String _applicationStatus(String status) {
    switch (status.trim().toLowerCase()) {
      case 'approved':
        return 'đã duyệt';
      case 'rejected':
        return 'từ chối';
      case 'reviewing':
        return 'chờ duyệt';
      default:
        return status;
    }
  }
}

class _LoanCell extends StatelessWidget {
  const _LoanCell({
    required this.loan,
  });

  final Loan? loan;

  @override
  Widget build(BuildContext context) {
    if (loan == null) return const Text('-');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppFormatters.currency(loan!.principal)),
        Text(
          '${AppFormatters.currency(loan!.netDisbursement)} thực nhận',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6B7A90),
              ),
        ),
      ],
    );
  }
}
