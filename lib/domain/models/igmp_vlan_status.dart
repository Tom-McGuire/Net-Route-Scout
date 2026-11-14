class IgmpVlanStatus {
  final int vlanId;
  final String? vlanName;
  final bool snoopingEnabled;
  final bool localQuerierEnabled;
  final String? activeQuerierIp;
  final int igmpVersion;
  final bool isLocalSwitchQuerier;

  const IgmpVlanStatus({
    required this.vlanId,
    this.vlanName,
    required this.snoopingEnabled,
    this.localQuerierEnabled = false,
    this.activeQuerierIp,
    this.igmpVersion = 2,
    this.isLocalSwitchQuerier = false,
  });

  Map<String, dynamic> toJson() => {
        'vlan_id': vlanId,
        'vlan_name': vlanName,
        'snooping_enabled': snoopingEnabled,
        'local_querier_enabled': localQuerierEnabled,
        'active_querier_ip': activeQuerierIp,
        'igmp_version': igmpVersion,
        'is_local_switch_querier': isLocalSwitchQuerier,
      };

  factory IgmpVlanStatus.fromJson(Map<String, dynamic> json) {
    return IgmpVlanStatus(
      vlanId: json['vlan_id'] as int? ?? 1,
      vlanName: json['vlan_name'] as String?,
      snoopingEnabled: json['snooping_enabled'] as bool? ?? false,
      localQuerierEnabled: json['local_querier_enabled'] as bool? ?? false,
      activeQuerierIp: json['active_querier_ip'] as String?,
      igmpVersion: json['igmp_version'] as int? ?? 2,
      isLocalSwitchQuerier: json['is_local_switch_querier'] as bool? ?? false,
    );
  }
}
