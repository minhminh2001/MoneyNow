import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../models/loan.dart';
import '../../models/loan_application.dart';
import '../../providers/app_providers.dart';

class AdminAnalyticsPanel extends ConsumerStatefulWidget {
  const AdminAnalyticsPanel({super.key});

  @override
  ConsumerState<AdminAnalyticsPanel> createState() => _AdminAnalyticsPanelState();
}

class _AdminAnalyticsPanelState extends ConsumerState<AdminAnalyticsPanel> {
  bool _loading = true;
  String? _error;
  List<LoanApplication> _applications = const [];
  List<Loan> _loans = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repository = ref.read(adminRepositoryProvider);
      final dashboard = await repository.fetchDashboard();
      if (!mounted) return;
      setState(() {
        _applications = dashboard.applications;
        _loans = dashboard.loans;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  int _applicationCount(String status) => _applications
      .where((application) => application.status.trim().toLowerCase() == status)
      .length;

  int _loanCount(String status) =>
      _loans.where((loan) => loan.status.trim().toLowerCase() == status).length;

  double _sumApplications() =>
      _applications.fold(0, (sum, application) => sum + application.amount);

  double _sumNetDisbursement() => _loans.fold(
      0, (sum, loan) => sum + loan.netDisbursement);

  double _sumOutstandingPrincipal() => _loans
      .where((loan) => loan.status.trim().toLowerCase() == 'active')
      .fold(0, (sum, loan) => sum + loan.principal);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text('Không thể tải biểu đồ và thống kê: $_error'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _AnalyticsStatCard(
                label: 'Tổng hồ sơ',
                value: '${_applications.length}',
              ),
              _AnalyticsStatCard(
                label: 'Tổng khoản vay',
                value: '${_loans.length}',
              ),
              _AnalyticsStatCard(
                label: 'Tổng tiền vay',
                value: AppFormatters.currency(_sumApplications()),
                wide: true,
              ),
              _AnalyticsStatCard(
                label: 'Đã giải ngân thực nhận',
                value: AppFormatters.currency(_sumNetDisbursement()),
                wide: true,
              ),
              _AnalyticsStatCard(
                label: 'Dư nợ active',
                value: AppFormatters.currency(_sumOutstandingPrincipal()),
                wide: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _AnalyticsSectionCard(
            title: 'Trạng thái hồ sơ vay',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatusMetric(
                  label: 'Chờ duyệt',
                  value: '${_applicationCount('reviewing')}',
                  color: const Color(0xFFE46A11),
                ),
                _StatusMetric(
                  label: 'Đã duyệt',
                  value: '${_applicationCount('approved')}',
                  color: const Color(0xFF2E7D32),
                ),
                _StatusMetric(
                  label: 'Từ chối',
                  value: '${_applicationCount('rejected')}',
                  color: const Color(0xFFC62828),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _AnalyticsSectionCard(
            title: 'Trạng thái khoản vay',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatusMetric(
                  label: 'Đang hoạt động',
                  value: '${_loanCount('active')}',
                  color: const Color(0xFF1565C0),
                ),
                _StatusMetric(
                  label: 'Đã đóng',
                  value: '${_loanCount('closed')}',
                  color: const Color(0xFF6D4C41),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _AnalyticsSectionCard(
            title: 'Ghi chú',
            child: Text(
              'Module này đang là bản web admin độc lập tối thiểu. Phần khách hàng chưa mở trên sidebar, còn thống kê đang lấy dữ liệu quản trị trực tiếp từ Firestore.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF5B6B7E),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsStatCard extends StatelessWidget {
  const _AnalyticsStatCard({
    required this.label,
    required this.value,
    this.wide = false,
  });

  final String label;
  final String value;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: wide ? 260 : 180,
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

class _AnalyticsSectionCard extends StatelessWidget {
  const _AnalyticsSectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF12343B),
                  ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatusMetric extends StatelessWidget {
  const _StatusMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}
