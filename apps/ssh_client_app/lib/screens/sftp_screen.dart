import 'dart:io';

import 'package:core_ssh/core_ssh.dart';
import 'package:core_vault/core_vault.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/vault_service.dart';

class SftpScreen extends StatefulWidget {
  const SftpScreen({super.key, required this.service});

  final VaultServiceInterface service;

  @override
  State<SftpScreen> createState() => _SftpScreenState();
}

class _SftpScreenState extends State<SftpScreen> {
  SshConnectionManager? _manager;
  SftpClient? _sftp;
  VaultHost? _connectedHost;
  String _currentPath = '/';
  List<SftpName> _entries = [];
  bool _loading = false;
  bool _transferring = false;
  String? _error;
  String? _transferStatus;
  bool _isDragging = false;

  @override
  void dispose() {
    _disconnect();
    super.dispose();
  }

  Future<void> _connectToHost(VaultHost host) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // Disconnect previous
    await _disconnect();

    // Find identity
    final identity = widget.service.currentData?.identities
        .where((i) => i.id == host.identityId)
        .firstOrNull;

    // Prompt for password
    final password = await _promptForPassword(host,
        hasKey: identity?.privateKey.isNotEmpty == true);
    if (password == null) {
      setState(() => _loading = false);
      return;
    }

    final manager = SshConnectionManager();
    try {
      final settings = widget.service.currentData?.settings;
      final keepaliveSecs = settings?.sshKeepaliveInterval ?? 30;

      await manager.connect(SshTarget(
        host: host.hostname,
        port: host.port,
        username: host.username,
        password: password.isNotEmpty ? password : null,
        privateKey: identity?.privateKey,
        passphrase: identity?.passphrase,
        keepAliveInterval:
            keepaliveSecs > 0 ? Duration(seconds: keepaliveSecs) : null,
      ));

      final sftp = await manager.openSftp();
      final homePath = await _resolveHome(sftp);

      setState(() {
        _manager = manager;
        _sftp = sftp;
        _connectedHost = host;
        _currentPath = homePath;
        _loading = false;
      });

      await _loadDirectory();
    } catch (e) {
      manager.dispose();
      setState(() {
        _loading = false;
        _error = e is SshException ? e.message : e.toString();
      });
    }
  }

  Future<String> _resolveHome(SftpClient sftp) async {
    try {
      final resolved = await sftp.absolute('.');
      return resolved;
    } catch (_) {
      return '/';
    }
  }

  Future<void> _disconnect() async {
    _sftp?.close();
    _sftp = null;
    await _manager?.disconnect();
    _manager?.dispose();
    _manager = null;
    if (mounted) {
      setState(() {
        _connectedHost = null;
        _entries = [];
        _currentPath = '/';
      });
    }
  }

  Future<void> _loadDirectory() async {
    if (_sftp == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final entries = await _sftp!.listdir(_currentPath);
      // Sort: directories first, then alphabetical
      entries.sort((a, b) {
        final aIsDir = a.attr.isDirectory;
        final bIsDir = b.attr.isDirectory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
      });
      // Remove . entry
      entries.removeWhere((e) => e.filename == '.');

      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _navigateTo(String dirName) async {
    if (dirName == '..') {
      final parent = _currentPath == '/'
          ? '/'
          : _currentPath.substring(
              0, _currentPath.lastIndexOf('/').clamp(0, _currentPath.length));
      _currentPath = parent.isEmpty ? '/' : parent;
    } else {
      _currentPath = _currentPath == '/'
          ? '/$dirName'
          : '$_currentPath/$dirName';
    }
    await _loadDirectory();
  }

  Future<void> _downloadFile(SftpName entry) async {
    if (_sftp == null) return;

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save ${entry.filename}',
      fileName: entry.filename,
    );
    if (savePath == null) return;

    setState(() {
      _transferring = true;
      _transferStatus = 'Downloading ${entry.filename}...';
    });

    try {
      final remotePath = _currentPath == '/'
          ? '/${entry.filename}'
          : '$_currentPath/${entry.filename}';
      final remoteFile =
          await _sftp!.open(remotePath, mode: SftpFileOpenMode.read);
      final data = await remoteFile.readBytes();
      await remoteFile.close();

      final localFile = File(savePath);
      await localFile.writeAsBytes(data, flush: true);

      _showMessage('Downloaded ${entry.filename}');
    } catch (e) {
      _showMessage('Download failed: $e');
    } finally {
      setState(() {
        _transferring = false;
        _transferStatus = null;
      });
    }
  }

  Future<void> _uploadFiles() async {
    if (_sftp == null) return;

    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    for (final file in result.files) {
      if (file.path == null) continue;
      await _uploadLocalFile(file.path!);
    }
    await _loadDirectory();
  }

  Future<void> _uploadLocalFile(String localPath) async {
    if (_sftp == null) return;

    final localFile = File(localPath);
    final fileName = localPath.split(Platform.pathSeparator).last;

    setState(() {
      _transferring = true;
      _transferStatus = 'Uploading $fileName...';
    });

    try {
      final data = await localFile.readAsBytes();
      final remotePath = _currentPath == '/'
          ? '/$fileName'
          : '$_currentPath/$fileName';
      final remoteFile = await _sftp!.open(remotePath,
          mode: SftpFileOpenMode.create |
              SftpFileOpenMode.write |
              SftpFileOpenMode.truncate);
      await remoteFile.writeBytes(data);
      await remoteFile.close();

      _showMessage('Uploaded $fileName');
    } catch (e) {
      _showMessage('Upload failed: $e');
    } finally {
      setState(() {
        _transferring = false;
        _transferStatus = null;
      });
    }
  }

  Future<void> _deleteEntry(SftpName entry) async {
    if (_sftp == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('Delete "${entry.filename}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final remotePath = _currentPath == '/'
          ? '/${entry.filename}'
          : '$_currentPath/${entry.filename}';
      if (entry.attr.isDirectory) {
        await _sftp!.rmdir(remotePath);
      } else {
        await _sftp!.remove(remotePath);
      }
      _showMessage('Deleted ${entry.filename}');
      await _loadDirectory();
    } catch (e) {
      _showMessage('Delete failed: $e');
    }
  }

  Future<void> _createFolder() async {
    if (_sftp == null) return;

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Folder name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name == null || name.trim().isEmpty) return;

    try {
      final remotePath = _currentPath == '/'
          ? '/${name.trim()}'
          : '$_currentPath/${name.trim()}';
      await _sftp!.mkdir(remotePath);
      _showMessage('Created folder ${name.trim()}');
      await _loadDirectory();
    } catch (e) {
      _showMessage('Failed to create folder: $e');
    }
  }

  Future<String?> _promptForPassword(VaultHost host,
      {bool hasKey = false}) async {
    final controller = TextEditingController();
    return showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('SFTP Authentication'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${host.username}@${host.hostname}:${host.port}'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Password',
                hintText: hasKey ? 'Leave empty for key auth' : null,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => Navigator.pop(context, controller.text),
            ),
            if (hasKey) ...[
              const SizedBox(height: 8),
              Text(
                'A private key is configured. Leave empty for key auth.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DropTarget(
      onDragDone: (details) async {
        if (_sftp == null) return;
        for (final file in details.files) {
          await _uploadLocalFile(file.path);
        }
        await _loadDirectory();
      },
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      child: Stack(
        children: [
          Column(
            children: [
              _buildToolbar(colorScheme),
              if (_transferring) _buildTransferBar(colorScheme),
              Expanded(
                child: _connectedHost == null
                    ? _buildDisconnectedState(colorScheme)
                    : _buildFileBrowser(colorScheme),
              ),
              if (_connectedHost != null) _buildActionBar(colorScheme),
            ],
          ),
          // Drag overlay
          if (_isDragging)
            Positioned.fill(
              child: Container(
                color: colorScheme.primary.withValues(alpha: 0.15),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_upload,
                          size: 64, color: colorScheme.primary),
                      const SizedBox(height: 12),
                      Text(
                        'Drop files to upload',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                      if (_connectedHost != null)
                        Text(
                          'to $_currentPath',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToolbar(ColorScheme colorScheme) {
    final hosts = widget.service.currentData?.hosts ?? [];

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          // Host selector
          DropdownButton<VaultHost>(
            value: _connectedHost,
            hint: const Text('Select host...'),
            underline: const SizedBox.shrink(),
            items: hosts.map((h) {
              return DropdownMenuItem(
                value: h,
                child: Text(h.label, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (host) {
              if (host != null) _connectToHost(host);
            },
          ),
          if (_connectedHost != null) ...[
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right, size: 16),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                _currentPath,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: colorScheme.onSurface.withValues(alpha: 0.8),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_upward, size: 18),
              tooltip: 'Parent directory',
              onPressed: _loading ? null : () => _navigateTo('..'),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: 'Refresh',
              onPressed: _loading ? null : _loadDirectory,
              visualDensity: VisualDensity.compact,
            ),
          ] else
            const Expanded(child: SizedBox.shrink()),
          if (_connectedHost != null)
            IconButton(
              icon: const Icon(Icons.link_off, size: 18),
              tooltip: 'Disconnect',
              onPressed: _disconnect,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _buildTransferBar(ColorScheme colorScheme) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: colorScheme.primaryContainer,
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            _transferStatus ?? 'Transferring...',
            style: TextStyle(fontSize: 12, color: colorScheme.onPrimaryContainer),
          ),
        ],
      ),
    );
  }

  Widget _buildDisconnectedState(ColorScheme colorScheme) {
    final hosts = widget.service.currentData?.hosts ?? [];

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_outlined,
              size: 64, color: colorScheme.primary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            'SFTP File Browser',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hosts.isEmpty
                ? 'Add hosts in the Hosts tab to browse files.'
                : 'Select a host to browse remote files.',
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
          ],
          if (_loading) ...[
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
            const SizedBox(height: 8),
            const Text('Connecting...'),
          ],
        ],
      ),
    );
  }

  Widget _buildFileBrowser(ColorScheme colorScheme) {
    if (_loading && _entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: colorScheme.error)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadDirectory,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_entries.isEmpty) {
      return Center(
        child: Text(
          'Empty directory',
          style: TextStyle(
            color: colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final entry = _entries[index];
        return _buildFileEntry(entry, colorScheme);
      },
    );
  }

  Widget _buildFileEntry(SftpName entry, ColorScheme colorScheme) {
    final isDir = entry.attr.isDirectory;
    final isLink = entry.longname.startsWith('l');
    final isDotDot = entry.filename == '..';
    final size = entry.attr.size;

    return ListTile(
      leading: Icon(
        isDotDot
            ? Icons.arrow_upward
            : isLink
                ? Icons.link
                : isDir
                    ? Icons.folder
                    : _fileIcon(entry.filename),
        color: isDir ? colorScheme.primary : colorScheme.onSurface.withValues(alpha: 0.7),
      ),
      title: Text(
        entry.filename,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          fontWeight: isDir ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: isDotDot
          ? null
          : Text(
              '${_formatSize(size)}  ${_formatPermissions(entry.longname)}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
      trailing: isDotDot
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isDir)
                  IconButton(
                    icon: const Icon(Icons.download, size: 18),
                    tooltip: 'Download',
                    onPressed: _transferring ? null : () => _downloadFile(entry),
                    visualDensity: VisualDensity.compact,
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'Delete',
                  onPressed: _transferring ? null : () => _deleteEntry(entry),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
      onTap: isDir ? () => _navigateTo(entry.filename) : null,
      dense: true,
    );
  }

  Widget _buildActionBar(ColorScheme colorScheme) {
    final fileCount = _entries.where((e) => e.filename != '..').length;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: _transferring ? null : _uploadFiles,
            icon: const Icon(Icons.upload, size: 16),
            label: const Text('Upload'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 32),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _transferring ? null : _createFolder,
            icon: const Icon(Icons.create_new_folder, size: 16),
            label: const Text('New Folder'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 32),
            ),
          ),
          const Spacer(),
          Text(
            '$fileCount item${fileCount != 1 ? 's' : ''}',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  IconData _fileIcon(String filename) {
    final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'txt' || 'md' || 'log' || 'conf' || 'cfg' || 'ini' || 'yaml' || 'yml' || 'toml' ||
      'json' || 'xml' || 'csv' => Icons.description,
      'dart' || 'py' || 'js' || 'ts' || 'java' || 'c' || 'cpp' || 'h' || 'rs' ||
      'go' || 'rb' || 'php' || 'sh' || 'bash' || 'zsh' => Icons.code,
      'jpg' || 'jpeg' || 'png' || 'gif' || 'bmp' || 'svg' || 'webp' => Icons.image,
      'mp4' || 'avi' || 'mkv' || 'mov' || 'webm' => Icons.movie,
      'mp3' || 'wav' || 'flac' || 'ogg' || 'aac' => Icons.music_note,
      'zip' || 'tar' || 'gz' || 'bz2' || 'xz' || '7z' || 'rar' => Icons.archive,
      'pdf' => Icons.picture_as_pdf,
      'key' || 'pem' || 'crt' || 'cer' => Icons.vpn_key,
      _ => Icons.insert_drive_file,
    };
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatPermissions(String longname) {
    // longname is like "-rw-r--r--  1 user group  1234 Jan 15 10:30 filename"
    if (longname.length < 10) return '';
    return longname.substring(0, 10);
  }
}
