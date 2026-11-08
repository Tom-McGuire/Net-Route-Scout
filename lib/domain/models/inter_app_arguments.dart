class InterAppArguments {
  final String? target;
  final String? subnet;
  final String? adapterIp;
  final String? adapterName;
  final bool autoStart;

  const InterAppArguments({
    this.target,
    this.subnet,
    this.adapterIp,
    this.adapterName,
    this.autoStart = false,
  });

  /// Parses command line arguments (e.g. `--target <ip>`, `--adapter-ip <ip>`, etc.)
  factory InterAppArguments.fromArgs(List<String> args) {
    String? target;
    String? subnet;
    String? adapterIp;
    String? adapterName;
    bool autoStart = false;

    for (int i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--target' && i + 1 < args.length) {
        target = args[++i];
      } else if (arg == '--subnet' && i + 1 < args.length) {
        subnet = args[++i];
      } else if (arg == '--adapter-ip' && i + 1 < args.length) {
        adapterIp = args[++i];
      } else if (arg == '--adapter-name' && i + 1 < args.length) {
        adapterName = args[++i];
      } else if (arg == '--auto-start') {
        autoStart = true;
      }
    }

    return InterAppArguments(
      target: target,
      subnet: subnet,
      adapterIp: adapterIp,
      adapterName: adapterName,
      autoStart: autoStart,
    );
  }

  /// Parses JSON payload received over loopback IPC socket.
  factory InterAppArguments.fromJson(Map<String, dynamic> json) {
    return InterAppArguments(
      target: json['target'] as String?,
      subnet: json['subnet'] as String?,
      adapterIp: json['adapterIp'] as String?,
      adapterName: json['adapterName'] as String?,
      autoStart: json['autoStart'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    if (target != null) 'target': target,
    if (subnet != null) 'subnet': subnet,
    if (adapterIp != null) 'adapterIp': adapterIp,
    if (adapterName != null) 'adapterName': adapterName,
    'autoStart': autoStart,
  };
}
