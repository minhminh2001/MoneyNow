import 'package:flutter/material.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.status,
  });

  final String status;

  Color _backgroundColor() {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'active':
      case 'paid':
      case 'verified':
      case 'closed':
        return const Color(0xFFFFE3CC);
      case 'reviewing':
      case 'submitted':
      case 'pending':
        return const Color(0xFFFFEBD7);
      case 'rejected':
      case 'overdue':
        return Colors.red.shade100;
      default:
        return const Color(0xFFFFF1E6);
    }
  }

  Color _foregroundColor() {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'active':
      case 'paid':
      case 'verified':
      case 'closed':
        return const Color(0xFF9D470D);
      case 'reviewing':
      case 'submitted':
      case 'pending':
        return const Color(0xFFB85B16);
      case 'rejected':
      case 'overdue':
        return Colors.red.shade900;
      default:
        return const Color(0xFF9D470D);
    }
  }

  String _label() {
    switch (status.toLowerCase()) {
      case 'approved':
        return 'Đã duyệt';
      case 'reviewing':
        return 'Đang thẩm định';
      case 'rejected':
        return 'Từ chối';
      case 'active':
        return 'Đang vay';
      case 'closed':
        return 'Đã đóng';
      case 'overdue':
        return 'Quá hạn';
      case 'paid':
        return 'Đã trả';
      case 'unpaid':
        return 'Chưa trả';
      case 'verified':
        return 'Đã xác minh';
      case 'submitted':
        return 'Đã nộp';
      case 'pending':
        return 'Chờ xử lý';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(_label()),
      backgroundColor: _backgroundColor(),
      labelStyle: TextStyle(
        color: _foregroundColor(),
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}
