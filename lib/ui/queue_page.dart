import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/audio_capture.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';
import '../services/connectivity_service.dart';

class QueuePage extends StatefulWidget {
  const QueuePage({super.key});

  @override
  State<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> {
  late Future<List<AudioCapture>> _future;
  final DatabaseService _db = DatabaseService();
  final SyncService _sync = SyncService();
  final ConnectivityService _connectivity = ConnectivityService();

  @override
  void initState() {
    super.initState();
    _future = _loadQueue();
    
    // Listen to sync service changes
    _sync.addListener(_onSyncChanged);
    _connectivity.addListener(_onConnectivityChanged);
  }

  @override
  void dispose() {
    _sync.removeListener(_onSyncChanged);
    _connectivity.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  void _onSyncChanged() {
    if (mounted) {
      setState(() {
        _future = _loadQueue();
      });
    }
  }

  void _onConnectivityChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<List<AudioCapture>> _loadQueue() async {
    try {
      return await _db.getAllCaptures();
    } catch (e) {
      debugPrint('Failed to load queue: $e');
      return [];
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadQueue();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Queue'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: 'Refresh',
          ),
          if (_connectivity.isConnected)
            IconButton(
              icon: _sync.isSyncing 
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload),
              onPressed: _sync.isSyncing ? null : _triggerSync,
              tooltip: 'Sync Now',
            ),
        ],
      ),
      body: FutureBuilder<List<AudioCapture>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final captures = snapshot.data ?? [];
          final totalSize = captures.fold<int>(0, (a, b) => a + b.fileSizeBytes);
          
          return Column(
            children: [
              _QueueSummary(
                captures: captures,
                totalBytes: totalSize,
                isConnected: _connectivity.isConnected,
                isSyncing: _sync.isSyncing,
                syncProgress: _sync.syncProgress,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: captures.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.queue, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('No captures in queue'),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: captures.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          padding: const EdgeInsets.all(12),
                          itemBuilder: (context, i) => _CaptureCard(
                            capture: captures[i],
                            onRetry: _retryCapture,
                            onDelete: _deleteCapture,
                          ),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _triggerSync() async {
    try {
      await _sync.triggerSync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync started')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    }
  }

  Future<void> _retryCapture(String captureId) async {
    try {
      await _sync.retryCapture(captureId);
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Retry failed: $e')),
        );
      }
    }
  }

  Future<void> _deleteCapture(String captureId) async {
    try {
      await _db.deleteCapture(captureId);
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }
}

class _QueueSummary extends StatelessWidget {
  final List<AudioCapture> captures;
  final int totalBytes;
  final bool isConnected;
  final bool isSyncing;
  final double syncProgress;
  
  const _QueueSummary({
    required this.captures,
    required this.totalBytes,
    required this.isConnected,
    required this.isSyncing,
    required this.syncProgress,
  });

  @override
  Widget build(BuildContext context) {
    final pendingCount = captures.where((c) => c.status.isPending).length;
    final completedCount = captures.where((c) => c.status == CaptureStatus.completed).length;
    final failedCount = captures.where((c) => c.status == CaptureStatus.failed).length;
    
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Connection status
            Row(
              children: [
                Icon(
                  isConnected ? Icons.cloud : Icons.cloud_off,
                  color: isConnected ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  isConnected ? 'Online' : 'Offline',
                  style: TextStyle(
                    color: isConnected ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (isSyncing) ...[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text('Syncing... ${(syncProgress * 100).toStringAsFixed(0)}%'),
                ],
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Statistics
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _SummaryChip(
                  icon: Icons.pending,
                  label: 'Pending',
                  value: '$pendingCount',
                  color: Colors.orange,
                ),
                _SummaryChip(
                  icon: Icons.check_circle,
                  label: 'Completed',
                  value: '$completedCount',
                  color: Colors.green,
                ),
                _SummaryChip(
                  icon: Icons.error,
                  label: 'Failed',
                  value: '$failedCount',
                  color: Colors.red,
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _SummaryChip(
                  icon: Icons.queue,
                  label: 'Total',
                  value: '${captures.length}',
                ),
                _SummaryChip(
                  icon: Icons.sd_storage,
                  label: 'Size',
                  value: _formatBytes(totalBytes),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  
  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? Colors.deepPurple;
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: chipColor.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: chipColor),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: chipColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptureCard extends StatelessWidget {
  final AudioCapture capture;
  final Function(String) onRetry;
  final Function(String) onDelete;
  
  const _CaptureCard({
    required this.capture,
    required this.onRetry,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getStatusColor().withOpacity(0.2),
          child: Icon(
            _getStatusIcon(),
            color: _getStatusColor(),
          ),
        ),
        title: Text(
          'Capture ${capture.id.substring(0, 8)}...',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_formatBytes(capture.fileSizeBytes)} • ${_formatTime(capture.capturedAt)}'),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getStatusColor().withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    capture.status.displayName,
                    style: TextStyle(
                      fontSize: 10,
                      color: _getStatusColor(),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (capture.retryCount > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    'Retries: ${capture.retryCount}',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ],
            ),
            if (capture.errorMessage != null) ...[
              const SizedBox(height: 4),
              Text(
                capture.errorMessage!,
                style: const TextStyle(fontSize: 10, color: Colors.red),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) => _handleAction(context, action),
          itemBuilder: (context) => [
            if (capture.status.canRetry)
              const PopupMenuItem(
                value: 'retry',
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 16),
                    SizedBox(width: 8),
                    Text('Retry'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 16, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'details',
              child: Row(
                children: [
                  Icon(Icons.info, size: 16),
                  SizedBox(width: 8),
                  Text('Details'),
                ],
              ),
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  Color _getStatusColor() {
    switch (capture.status) {
      case CaptureStatus.pending:
      case CaptureStatus.retrying:
        return Colors.orange;
      case CaptureStatus.uploading:
        return Colors.blue;
      case CaptureStatus.completed:
        return Colors.green;
      case CaptureStatus.failed:
        return Colors.red;
    }
  }

  IconData _getStatusIcon() {
    switch (capture.status) {
      case CaptureStatus.pending:
        return Icons.schedule;
      case CaptureStatus.uploading:
        return Icons.cloud_upload;
      case CaptureStatus.completed:
        return Icons.check_circle;
      case CaptureStatus.failed:
        return Icons.error;
      case CaptureStatus.retrying:
        return Icons.refresh;
    }
  }

  void _handleAction(BuildContext context, String action) {
    switch (action) {
      case 'retry':
        onRetry(capture.id);
        break;
      case 'delete':
        _showDeleteConfirmation(context);
        break;
      case 'details':
        _showDetails(context);
        break;
    }
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Capture'),
        content: const Text('Are you sure you want to delete this capture? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onDelete(capture.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Capture Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _DetailRow('ID', capture.id),
              _DetailRow('Station', capture.stationId),
              _DetailRow('Status', capture.status.displayName),
              _DetailRow('Captured At', _formatDateTime(capture.capturedAt)),
              _DetailRow('Duration', '${capture.durationSeconds}s'),
              _DetailRow('File Size', _formatBytes(capture.fileSizeBytes)),
              _DetailRow('Retry Count', '${capture.retryCount}'),
              if (capture.lastRetryAt != null)
                _DetailRow('Last Retry', _formatDateTime(capture.lastRetryAt!)),
              if (capture.errorMessage != null)
                _DetailRow('Error', capture.errorMessage!),
              if (capture.metadata != null && capture.metadata!.isNotEmpty)
                _DetailRow('Metadata', capture.metadata.toString()),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime time) {
    final local = time.toLocal();
    return '${local.day}/${local.month}/${local.year} ${_formatTime(time)}';
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}


