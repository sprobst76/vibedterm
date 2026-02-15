import 'dart:convert';
import 'dart:io';

/// A discovered Tailscale peer node.
class TailscaleNode {
  const TailscaleNode({
    required this.hostName,
    required this.dnsName,
    required this.tailscaleIPs,
    required this.os,
    required this.online,
    this.userName,
    this.tags = const [],
  });

  final String hostName;
  final String dnsName;
  final List<String> tailscaleIPs;
  final String os;
  final bool online;
  final String? userName;
  final List<String> tags;

  /// The preferred connection address (first Tailscale IP).
  String get preferredAddress =>
      tailscaleIPs.isNotEmpty ? tailscaleIPs.first : dnsName;
}

/// Result of a Tailscale node discovery scan.
class TailscaleDiscoveryResult {
  const TailscaleDiscoveryResult({
    required this.nodes,
    this.selfNode,
    this.error,
  });

  final List<TailscaleNode> nodes;
  final TailscaleNode? selfNode;
  final String? error;
}

/// Discovers Tailscale peers by running `tailscale status --json`.
Future<TailscaleDiscoveryResult> discoverTailscaleNodes() async {
  try {
    final result = await Process.run('tailscale', ['status', '--json']);
    if (result.exitCode != 0) {
      return TailscaleDiscoveryResult(
        nodes: [],
        error:
            'tailscale exited with code ${result.exitCode}: ${result.stderr}',
      );
    }

    final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;

    // Parse User map for display names
    final users = <String, String>{};
    final userMap = json['User'] as Map<String, dynamic>? ?? {};
    for (final entry in userMap.entries) {
      final user = entry.value as Map<String, dynamic>;
      users[entry.key] = (user['LoginName'] as String?) ?? '';
    }

    // Parse peers
    final peers = json['Peer'] as Map<String, dynamic>? ?? {};
    final nodes = <TailscaleNode>[];
    for (final peer in peers.values) {
      final p = peer as Map<String, dynamic>;
      nodes.add(TailscaleNode(
        hostName: p['HostName'] as String? ?? '',
        dnsName: p['DNSName'] as String? ?? '',
        tailscaleIPs: (p['TailscaleIPs'] as List?)?.cast<String>() ?? [],
        os: p['OS'] as String? ?? '',
        online: p['Online'] as bool? ?? false,
        userName: users[p['UserID']?.toString()],
        tags: (p['Tags'] as List?)?.cast<String>() ?? [],
      ));
    }

    // Parse self node
    TailscaleNode? selfNode;
    final self = json['Self'] as Map<String, dynamic>?;
    if (self != null) {
      selfNode = TailscaleNode(
        hostName: self['HostName'] as String? ?? '',
        dnsName: self['DNSName'] as String? ?? '',
        tailscaleIPs: (self['TailscaleIPs'] as List?)?.cast<String>() ?? [],
        os: self['OS'] as String? ?? '',
        online: true,
        userName: users[self['UserID']?.toString()],
      );
    }

    return TailscaleDiscoveryResult(nodes: nodes, selfNode: selfNode);
  } on ProcessException {
    return const TailscaleDiscoveryResult(
      nodes: [],
      error: 'Tailscale CLI not found. Is Tailscale installed?',
    );
  }
}
