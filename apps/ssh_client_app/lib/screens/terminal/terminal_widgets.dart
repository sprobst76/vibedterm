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

  Widget _buildHostTile(
      BuildContext context, VaultHost host, List<VaultIdentity> identities) {
    final identity =
        identities.where((i) => i.id == host.identityId).firstOrNull;
    return ListTile(
      leading: const Icon(Icons.dns),
      title: Text(host.label),
      subtitle: Text('${host.username}@${host.hostname}:${host.port}'),
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
  }

  @override
  Widget build(BuildContext context) {
    final groups = hosts
        .map((h) => h.group)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
    final ungrouped = hosts.where((h) => h.group == null).toList();

    final items = <Widget>[];
    for (final groupName in groups) {
      final groupHosts = hosts.where((h) => h.group == groupName).toList();
      items.add(
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
          child: Text(
            groupName,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
      );
      items.addAll(
          groupHosts.map((h) => _buildHostTile(context, h, identities)));
    }
    if (ungrouped.isNotEmpty && groups.isNotEmpty) {
      items.add(
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
          child: Text(
            'Ungrouped',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ),
      );
    }
    items
        .addAll(ungrouped.map((h) => _buildHostTile(context, h, identities)));

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
          child: ListView(
            shrinkWrap: true,
            children: items,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
