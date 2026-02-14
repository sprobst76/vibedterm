part of 'terminal_screen.dart';

// -----------------------------------------------------------------------------
// Key Button Widget
// -----------------------------------------------------------------------------

class _KeyButton extends StatelessWidget {
  const _KeyButton({required this.label, this.onPressed, this.textColor});

  final String label;
  final VoidCallback? onPressed;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final color = textColor ?? Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 32),
          visualDensity: VisualDensity.compact,
          foregroundColor: color,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: onPressed != null ? color : color.withValues(alpha:0.4),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Host Picker Sheet
// -----------------------------------------------------------------------------

class _HostPickerSheet extends StatelessWidget {
  const _HostPickerSheet({
    required this.hosts,
    required this.identities,
  });

  final List<VaultHost> hosts;
  final List<VaultIdentity> identities;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Connect to host',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const Divider(height: 1),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: hosts.length,
            itemBuilder: (context, index) {
              final host = hosts[index];
              final identity =
                  identities.where((i) => i.id == host.identityId).firstOrNull;
              return ListTile(
                leading: const Icon(Icons.dns),
                title: Text(host.label),
                subtitle:
                    Text('${host.username}@${host.hostname}:${host.port}'),
                trailing: identity != null
                    ? Chip(
                        label: Text(
                          identity.name,
                          style: const TextStyle(fontSize: 10),
                        ),
                        visualDensity: VisualDensity.compact,
                      )
                    : null,
                onTap: () => Navigator.pop(context, host),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
