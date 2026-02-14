part of 'terminal_screen.dart';

// -----------------------------------------------------------------------------
// tmux Session Manager
// -----------------------------------------------------------------------------

enum TmuxAction { attach, detach, newSession, killSession }

/// Represents a parsed tmux session from `tmux list-sessions` output.
class TmuxSession {
  const TmuxSession({
    required this.name,
    required this.windows,
    required this.created,
    this.attached = false,
  });

  final String name;
  final int windows;
  final String created;
  final bool attached;

  /// Parse tmux list-sessions output.
  /// Format: "session_name: N windows (created Day Mon DD HH:MM:SS YYYY) (attached)"
  static List<TmuxSession> parseListSessions(String output) {
    final sessions = <TmuxSession>[];
    final lines = output.split('\n').where((l) => l.trim().isNotEmpty);

    for (final line in lines) {
      // Skip error messages
      if (line.startsWith('error:') ||
          line.startsWith('no server') ||
          line.contains('no sessions')) {
        continue;
      }

      // Parse: "name: N windows (created ...)"
      final colonIdx = line.indexOf(':');
      if (colonIdx < 0) continue;

      final name = line.substring(0, colonIdx).trim();
      final rest = line.substring(colonIdx + 1).trim();

      // Extract window count
      final windowsMatch = RegExp(r'(\d+) windows?').firstMatch(rest);
      final windows = windowsMatch != null
          ? int.tryParse(windowsMatch.group(1) ?? '1') ?? 1
          : 1;

      // Check if attached
      final attached = rest.contains('(attached)');

      // Extract created time (simplified)
      final createdMatch = RegExp(r'\(created ([^)]+)\)').firstMatch(rest);
      final created = createdMatch?.group(1) ?? '';

      sessions.add(TmuxSession(
        name: name,
        windows: windows,
        created: created,
        attached: attached,
      ));
    }

    return sessions;
  }
}

class _TmuxSessionManagerDialog extends StatefulWidget {
  const _TmuxSessionManagerDialog({
    required this.tab,
    required this.onSessionAction,
  });

  final _ConnectionTab tab;
  final Future<void> Function(TmuxAction action, String? sessionName)
      onSessionAction;

  @override
  State<_TmuxSessionManagerDialog> createState() =>
      _TmuxSessionManagerDialogState();
}

class _TmuxSessionManagerDialogState extends State<_TmuxSessionManagerDialog> {
  List<TmuxSession>? _sessions;
  bool _loading = true;
  String? _error;
  final _newSessionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final session = widget.tab.session;
      if (session == null) {
        setState(() {
          _loading = false;
          _error = 'No active session';
        });
        return;
      }

      // Clear some buffer space and send command
      await session.writeString('tmux list-sessions 2>&1\n');

      // Wait for output
      await Future.delayed(const Duration(milliseconds: 500));

      setState(() {
        _loading = false;
        _sessions = []; // Placeholder - real parsing would happen here
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.grid_view),
          const SizedBox(width: 12),
          const Expanded(child: Text('tmux Sessions')),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadSessions,
            tooltip: 'Refresh',
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        height: 350,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Quick actions
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () =>
                      widget.onSessionAction(TmuxAction.newSession, null),
                  icon: const Icon(Icons.add),
                  label: const Text('New session'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      widget.onSessionAction(TmuxAction.attach, null),
                  icon: const Icon(Icons.login),
                  label: const Text('Attach (default)'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      widget.onSessionAction(TmuxAction.detach, null),
                  icon: const Icon(Icons.logout),
                  label: const Text('Detach'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // New session with name
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newSessionController,
                    decoration: const InputDecoration(
                      hintText: 'Session name (optional)',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final name = _newSessionController.text.trim();
                    widget.onSessionAction(
                      TmuxAction.newSession,
                      name.isEmpty ? null : name,
                    );
                  },
                  child: const Text('Create'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // Session list header
            Text(
              'Active Sessions',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),

            // Session list
            Expanded(
              child: _buildSessionList(),
            ),

            // Tip
            const SizedBox(height: 8),
            Text(
              'Tip: Press Ctrl+B, d to detach from tmux',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildSessionList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade400, size: 32),
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadSessions,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final sessions = _sessions;
    if (sessions == null || sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.grid_view, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            const Text(
              'Use "tmux list-sessions" to see sessions.\n'
              'Session list auto-detection coming soon.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        return ListTile(
          leading: Icon(
            session.attached ? Icons.visibility : Icons.grid_view,
            color: session.attached ? Colors.green : null,
          ),
          title: Text(session.name),
          subtitle: Text(
            '${session.windows} window${session.windows > 1 ? 's' : ''}'
            '${session.attached ? ' (attached)' : ''}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!session.attached)
                IconButton(
                  icon: const Icon(Icons.login),
                  tooltip: 'Attach',
                  onPressed: () => widget.onSessionAction(
                    TmuxAction.attach,
                    session.name,
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Kill session',
                onPressed: () => _confirmKillSession(session.name),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmKillSession(String sessionName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kill session?'),
        content: Text('Are you sure you want to kill tmux session "$sessionName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Kill'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.onSessionAction(TmuxAction.killSession, sessionName);
    }
  }
}

// -----------------------------------------------------------------------------
// tmux Session Picker Dialog (shown when multiple sessions exist)
// -----------------------------------------------------------------------------

class _TmuxSessionPickerDialog extends StatelessWidget {
  const _TmuxSessionPickerDialog({required this.sessions});

  final List<TmuxSession> sessions;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.grid_view),
          SizedBox(width: 12),
          Text('Select tmux Session'),
        ],
      ),
      content: SizedBox(
        width: 350,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Multiple tmux sessions found. Choose one to attach:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: sessions.length,
                itemBuilder: (context, index) {
                  final session = sessions[index];
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        session.attached ? Icons.visibility : Icons.grid_view,
                        color: session.attached ? Colors.green : null,
                      ),
                      title: Text(
                        session.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${session.windows} window${session.windows > 1 ? 's' : ''}'
                        '${session.attached ? ' • attached' : ''}',
                      ),
                      onTap: () => Navigator.pop(context, session.name),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Create new session'),
              contentPadding: EdgeInsets.zero,
              onTap: () => Navigator.pop(context, ''),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Skip tmux'),
        ),
      ],
    );
  }
}
