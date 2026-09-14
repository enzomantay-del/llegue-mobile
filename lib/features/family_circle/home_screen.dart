import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/brand_mark.dart';
import '../places/places_screen.dart';
import '../routines/routines_screen.dart';
import '../settings/alert_prefs_screen.dart';
import '../settings/help_screen.dart';
import '../settings/profile_screen.dart';
import '../settings/settings_hub_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  static const route = '/home';

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  bool _busy = false;
  bool _loadingOlder = false;
  bool _olderLoaded = false;
  List<Map<String, dynamic>> _olderAlerts = [];

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final app = context.read<AppController>();
    try {
      await app.refreshFamilyStatus();
      await app.syncRuntimeServices();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _run(Future<void> Function() action, {String? okMsg}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      if (okMsg != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(okMsg)));
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo completar. Probá de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _invite() async {
    final nameCtrl = TextEditingController();
    var role = 'adult';
    final pinCtrl = TextEditingController();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Invitar a la familia',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Vos cargás el nombre. A esa persona le llega un solo link.',
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nombre',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Adulto'),
                          selected: role == 'adult',
                          onSelected: (_) => setModal(() => role = 'adult'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Hijo/a'),
                          selected: role == 'kid',
                          onSelected: (_) => setModal(() => role = 'kid'),
                        ),
                      ),
                    ],
                  ),
                  if (role == 'kid') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: pinCtrl,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'PIN (opcional)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(14)),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Crear invitación'),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );

    if (ok != true || !mounted) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Poné un nombre.')),
      );
      return;
    }

    final app = context.read<AppController>();
    try {
      final data = await app.createInvitation(
        name: name,
        role: role,
        pin: pinCtrl.text.trim().isEmpty ? null : pinCtrl.text.trim(),
      );
      final invite = data['invitation'] is Map
          ? Map<String, dynamic>.from(data['invitation'] as Map)
          : <String, dynamic>{};
      final inviteUrl = (data['inviteUrl'] as String?)?.trim().isNotEmpty == true
          ? data['inviteUrl'] as String
          : (invite['inviteUrl'] as String? ?? '');
      final code = invite['code'] as String? ?? '';
      final roleLabel = role == 'kid' ? 'hijo/a' : 'adulto';
      final shareMessage = (data['shareMessage'] as String?)?.trim().isNotEmpty == true
          ? data['shareMessage'] as String
          : 'Hola $name, te invito a Llegué como $roleLabel.\n\n'
              'Entrá acá: $inviteUrl\n\n'
              'Si te pide código: $code';

      if (inviteUrl.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo generar el link de invitación. Intentá de nuevo.',
            ),
          ),
        );
        return;
      }

      if (!mounted) return;
      final goWhatsApp = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Link listo'),
          content: Text(
            'Código: $code\n\n'
            'Se va a mandar este link:\n\n$inviteUrl\n\n'
            'Quien lo toque va a poder descargar Llegué y entrar como $roleLabel '
            '($name ya está cargado).',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: inviteUrl));
                if (context.mounted) Navigator.pop(context, false);
              },
              child: const Text('Solo copiar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Abrir WhatsApp'),
            ),
          ],
        ),
      );

      await Clipboard.setData(ClipboardData(text: shareMessage));
      if (goWhatsApp == true) {
        final encoded = Uri.encodeComponent(shareMessage);
        final uri = Uri.parse('whatsapp://send?text=$encoded');
        final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!opened) {
          await launchUrl(
            Uri.parse('https://wa.me/?text=$encoded'),
            mode: LaunchMode.externalApplication,
          );
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invitación lista para $name')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  Future<void> _editActiveTrip(Map trip) async {
    final app = context.read<AppController>();
    if (app.places.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero agregá un lugar.')),
      );
      return;
    }
    String? placeId = trip['destinationPlaceId'] as String?;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Cambiar destino',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: placeId != null &&
                            app.places.any((p) => p['id'] == placeId)
                        ? placeId
                        : app.places.first['id'] as String,
                    decoration: const InputDecoration(labelText: 'Lugar'),
                    items: [
                      for (final p in app.places)
                        DropdownMenuItem(
                          value: p['id'] as String,
                          child: Text(p['name'] as String? ?? 'Lugar'),
                        ),
                    ],
                    onChanged: (v) => setModal(() => placeId = v),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Guardar cambios'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (ok != true || !mounted || placeId == null) return;
    await _run(
      () async {
        await app.updateActiveTrip(
          tripId: trip['id'] as String,
          destinationPlaceId: placeId,
        );
      },
      okMsg: 'Destino actualizado',
    );
  }

  Future<void> _startOuting({String? forKidId, String? forKidName}) async {
    final app = context.read<AppController>();
    final isAdultForKid = app.isAdult && forKidId != null;
    String? placeId;
    var setReturn = false;
    var returnTime = TimeOfDay(
      hour: (TimeOfDay.now().hour + 2) % 24,
      minute: 0,
    );

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isAdultForKid
                        ? 'Salida especial de ${forKidName ?? 'tu hijo/a'}'
                        : 'Salida especial',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isAdultForKid
                        ? 'Elegí a dónde va. La app avisa sola cuando llegue (no hace falta que toque “Ya llegué”).'
                        : 'Elegí a dónde vas. La app avisa sola cuando llegues.',
                  ),
                  const SizedBox(height: 14),
                  if (app.places.isEmpty)
                    const Text(
                      'Todavía no hay lugares. Primero agregá o sugerí uno (ej. casa de un amigo).',
                    )
                  else
                    DropdownButtonFormField<String?>(
                      initialValue: placeId,
                      decoration: const InputDecoration(
                        labelText: '¿A dónde? (recomendado)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(14)),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Sin lugar fijo'),
                        ),
                        for (final p in app.places)
                          DropdownMenuItem(
                            value: p['id'] as String,
                            child: Text(p['name'] as String? ?? 'Lugar'),
                          ),
                      ],
                      onChanged: (v) => setModal(() => placeId = v),
                    ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Avisar si se demora'),
                    subtitle: Text(
                      setReturn
                          ? 'Vuelve alrededor de '
                              '${returnTime.hour.toString().padLeft(2, '0')}:'
                              '${returnTime.minute.toString().padLeft(2, '0')}'
                          : 'Sin hora de vuelta',
                    ),
                    value: setReturn,
                    onChanged: (v) => setModal(() => setReturn = v),
                  ),
                  if (setReturn)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: returnTime,
                          helpText: '¿A qué hora vuelve?',
                        );
                        if (picked != null) {
                          setModal(() => returnTime = picked);
                        }
                      },
                      icon: const Icon(Icons.schedule),
                      label: Text(
                        'Hora de vuelta '
                        '${returnTime.hour.toString().padLeft(2, '0')}:'
                        '${returnTime.minute.toString().padLeft(2, '0')}',
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Avisar salida'),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );

    if (ok != true || !mounted) return;

    String? expectedReturnAt;
    if (setReturn) {
      final now = DateTime.now();
      var dt = DateTime(
        now.year,
        now.month,
        now.day,
        returnTime.hour,
        returnTime.minute,
      );
      if (dt.isBefore(now)) dt = dt.add(const Duration(days: 1));
      expectedReturnAt = dt.toUtc().toIso8601String();
    }

    await _run(
      () async {
        await app.startTrip(
          kidId: forKidId,
          destinationPlaceId: placeId,
          expectedReturnAt: expectedReturnAt,
          forceNotify: false,
        );
      },
      okMsg: 'Salida armada',
    );
  }

  Future<void> _adultPickKidOuting() async {
    final app = context.read<AppController>();
    final kids = app.members.where((m) => m['role'] == 'kid').toList();
    if (kids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero invitá a un hijo/a.')),
      );
      return;
    }
    if (kids.length == 1) {
      await _startOuting(
        forKidId: kids.first['id'] as String,
        forKidName: kids.first['name'] as String?,
      );
      return;
    }
    final chosen = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  '¿De quién es la salida?',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              for (final k in kids)
                ListTile(
                  title: Text(k['name'] as String? ?? 'Hijo/a'),
                  onTap: () => Navigator.pop(context, k),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (chosen == null || !mounted) return;
    await _startOuting(
      forKidId: chosen['id'] as String,
      forKidName: chosen['name'] as String?,
    );
  }

  Future<void> _testAlerts() async {
    final app = context.read<AppController>();
    await app.alerts.showTestAlarm();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Prueba de alarma'),
        content: const Text(
          'Tenés que escuchar fuerte y sentir vibración. '
          'Si se oye bajo, subí el volumen de ALARMA del celular '
          '(no el de música).',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _openAdultMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Más opciones',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                ),
                _MenuTile(
                  icon: Icons.person_outline_rounded,
                  label: 'Mi perfil',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).pushNamed(ProfileScreen.route);
                  },
                ),
                _MenuTile(
                  icon: Icons.help_outline_rounded,
                  label: 'Ayuda',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).pushNamed(HelpScreen.route);
                  },
                ),
                _MenuTile(
                  icon: Icons.directions_walk_rounded,
                  label: 'Salida especial de un hijo/a',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _adultPickKidOuting();
                  },
                ),
                _MenuTile(
                  icon: Icons.notifications_outlined,
                  label: 'Qué avisos quiero recibir',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).pushNamed(AlertPrefsScreen.route);
                  },
                ),
                _MenuTile(
                  icon: Icons.alarm_rounded,
                  label: 'Probar la alarma',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _testAlerts();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadOlderAlerts() async {
    final app = context.read<AppController>();
    setState(() => _loadingOlder = true);
    try {
      List<Map<String, dynamic>> extra = [];
      try {
        final data = await app.api.listMyNotifications();
        extra = (data['notifications'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {
        final data = await app.api.listEvents();
        extra = (data['events'] as List<dynamic>? ?? []).map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return {
            'id': m['id'],
            'title': 'Llegué',
            'body': m['message'] ?? '',
            'createdAt': m['createdAt'],
          };
        }).toList();
      }
      if (!mounted) return;
      setState(() {
        _olderAlerts = extra;
        _olderLoaded = true;
        _loadingOlder = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  List<Map<String, dynamic>> _alertItems(AppController app) {
    final raw = app.notifications.isNotEmpty
        ? app.notifications
        : app.recentEvents.map((e) => <String, dynamic>{
              'id': e['id'],
              'title': 'Llegué',
              'body': e['message'] ?? '',
              'createdAt': e['createdAt'],
            });
    final primary =
        raw.map((n) => Map<String, dynamic>.from(n)).toList();
    if (_olderAlerts.isEmpty) return primary;
    final seen = <Object?>{
      for (final a in primary) a['id'] ?? '${a['body']}|${a['createdAt']}',
    };
    final merged = [...primary];
    for (final a in _olderAlerts) {
      final key = a['id'] ?? '${a['body']}|${a['createdAt']}';
      if (seen.add(key)) merged.add(a);
    }
    merged.sort((a, b) {
      final as = a['createdAt'] as String? ?? '';
      final bs = b['createdAt'] as String? ?? '';
      return bs.compareTo(as);
    });
    return merged;
  }

  Future<void> _suggestPlaceFromHome() async {
    Navigator.of(context).pushNamed(PlacesScreen.route);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final familyName = app.family?['name'] as String? ?? 'Tu familia';

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(decoration: appBrandGradientDecoration()),
          SafeArea(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : Stack(
                    children: [
                      RefreshIndicator(
                        color: AppColors.brandDeep,
                        backgroundColor: Colors.white,
                        onRefresh: _load,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
                          children: [
                            _TopBar(
                              familyName: familyName,
                              onOpenSettings: () => Navigator.of(context)
                                  .pushNamed(SettingsHubScreen.route),
                              onOpenMenu: app.isAdult ? _openAdultMenu : null,
                            ),
                            const SizedBox(height: 24),
                            if (app.isKid)
                              ..._buildKidHome(app)
                            else
                              ..._buildAdultHome(app),
                          ],
                        ),
                      ),
                      if (_busy)
                        ColoredBox(
                          color: Colors.black.withValues(alpha: 0.35),
                          child: const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAdultHome(AppController app) {
    final kids = app.members.where((m) => m['role'] == 'kid').toList();
    final primaryKid = kids.isNotEmpty ? kids.first : null;
    final alerts = _alertItems(app);

    return [
      if (primaryKid == null) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 30, 22, 28),
          decoration: appGlassDecoration(radius: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tu familia empieza acá',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Invitá a tu hijo o hija. Después vas a ver acá si está en casa, en camino o llegó.',
                style: GoogleFonts.dmSans(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),
              _PrimaryButton(
                label: 'Invitar hijo/a',
                onPressed: _invite,
              ),
            ],
          ),
        ),
      ] else
        _KidHeroCard(member: primaryKid),
      if (kids.length > 1) ...[
        const SizedBox(height: 12),
        ...kids.skip(1).map(
              (m) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _KidCompactRow(member: m),
              ),
            ),
      ],
      const SizedBox(height: 22),
      _PrimaryButton(
        label: 'Lugares de la familia',
        onPressed: () => Navigator.of(context).pushNamed(PlacesScreen.route),
      ),
      const SizedBox(height: 10),
      OutlinedButton(
        onPressed: () => Navigator.of(context).pushNamed(RoutinesScreen.route),
        child: const Text('Rutinas'),
      ),
      const SizedBox(height: 10),
      TextButton(
        onPressed: _invite,
        child: Text(
          'Invitar a alguien más',
          style: GoogleFonts.dmSans(
            color: Colors.white.withValues(alpha: 0.85),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      if (app.pendingPlaces.isNotEmpty) ...[
        const SizedBox(height: 18),
        Text(
          'Por aprobar',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        ...app.pendingPlaces.map((p) {
          final name = p['name'] as String? ?? 'Lugar';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              decoration: appGlassDecoration(radius: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: GoogleFonts.dmSans(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _run(
                      () async {
                        await app.approvePlace(p['id'] as String);
                      },
                      okMsg: 'Lugar aprobado: $name',
                    ),
                    child: Text(
                      'Aprobar',
                      style: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
      const SizedBox(height: 28),
      Text(
        'Últimos avisos',
        style: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 10),
      if (alerts.isEmpty)
        Text(
          'Cuando tu hijo/a llegue, salga o avise algo, aparece acá.',
          style: GoogleFonts.dmSans(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 14,
            height: 1.4,
          ),
        )
      else
        ...alerts.map((map) {
          return _AlertTile(
            body: map['body'] as String? ??
                map['title'] as String? ??
                'Aviso',
            when: map['createdAt'] as String?,
          );
        }),
      if (!_olderLoaded) ...[
        const SizedBox(height: 8),
        TextButton(
          onPressed: _loadingOlder ? null : _loadOlderAlerts,
          child: Text(
            _loadingOlder ? 'Cargando…' : 'Ver más antiguos',
            style: GoogleFonts.dmSans(
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildKidHome(AppController app) {
    final trip = app.activeTrip;
    final destName = trip?['destinationName'] as String?;
    final isHomeTrip =
        trip?['destinationType'] == 'home' || destName == 'Casa';

    return [
      Text(
        'Hola, ${app.displayName}',
        style: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          height: 1.1,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'Tu familia se entera sola cuando llegás o salís.',
        style: GoogleFonts.dmSans(
          color: Colors.white.withValues(alpha: 0.82),
          fontSize: 16,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 28),
      _PrimaryButton(
        label: 'Regreso a casa',
        height: 58,
        onPressed: () => _run(
          () async {
            await app.goHome();
          },
          okMsg: 'Avisaste: regreso a casa. Te avisamos solos al llegar.',
        ),
      ),
      const SizedBox(height: 12),
      _PrimaryButton(
        label: 'Salida especial',
        height: 58,
        onPressed: () => _startOuting(),
      ),
      const SizedBox(height: 12),
      _PrimaryButton(
        label: 'Sugerir un lugar',
        height: 58,
        onPressed: _suggestPlaceFromHome,
      ),
      if (trip != null) ...[
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          decoration: appGlassDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isHomeTrip
                    ? 'Regreso a casa en curso'
                    : (destName != null
                        ? 'En camino a $destName'
                        : 'Salida especial en curso'),
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                destName != null
                    ? 'La app avisa sola cuando llegues. No hace falta tocar nada.'
                    : 'Cuando llegues a un lugar guardado, la app avisa sola.',
                style: GoogleFonts.dmSans(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => _editActiveTrip(trip),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: Text(
                  'Cambiar destino',
                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: () => _run(
                  () async {
                    await app.cancelTrip(trip['id'] as String);
                  },
                  okMsg: 'Salida cancelada',
                ),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: Text(
                  'Cancelar salida',
                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: () => _run(
                  () async {
                    await app.arriveTrip(trip['id'] as String);
                  },
                  okMsg: 'Avisaste que llegaste (respaldo)',
                ),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white.withValues(alpha: 0.9),
                ),
                child: Text(
                  'Ya llegué (solo si falla el GPS)',
                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).pushNamed(PlacesScreen.route),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white.withValues(alpha: 0.85),
          ),
          child: Text(
            'Ver lugares',
            style: GoogleFonts.dmSans(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Center(
        child: TextButton(
          onPressed: () =>
              Navigator.of(context).pushNamed(SettingsHubScreen.route),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white.withValues(alpha: 0.85),
          ),
          child: Text(
            'Cuenta y ayuda',
            style: GoogleFonts.dmSans(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    ];
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.familyName,
    required this.onOpenSettings,
    this.onOpenMenu,
  });

  final String familyName;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenMenu;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onOpenMenu != null)
          IconButton(
            onPressed: onOpenMenu,
            tooltip: 'Menú',
            icon: const Icon(Icons.menu_rounded, color: Colors.white),
          ),
        const BrandMark(size: 36, showShadow: false),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Llegué',
                style: GoogleFonts.dmSans(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              Text(
                familyName,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onOpenSettings,
          tooltip: 'Cuenta',
          icon: const Icon(Icons.manage_accounts_rounded, color: Colors.white),
        ),
      ],
    );
  }
}

class _KidHeroCard extends StatelessWidget {
  const _KidHeroCard({required this.member});

  final Map<String, dynamic> member;

  @override
  Widget build(BuildContext context) {
    final label = member['presenceLabel'] as String? ?? 'Sin novedades';
    final last = member['lastEvent'] as Map?;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 26),
      decoration: appGlassDecoration(radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            member['name'] as String? ?? '',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
            ),
          ),
          if (last != null) ...[
            const SizedBox(height: 14),
            Text(
              last['message'] as String? ?? '',
              style: GoogleFonts.dmSans(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 15,
                height: 1.35,
              ),
            ),
            if (last['createdAt'] != null) ...[
              const SizedBox(height: 6),
              Text(
                _friendlyTime(last['createdAt'] as String),
                style: GoogleFonts.dmSans(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _KidCompactRow extends StatelessWidget {
  const _KidCompactRow({required this.member});

  final Map<String, dynamic> member;

  @override
  Widget build(BuildContext context) {
    final label = member['presenceLabel'] as String? ?? 'Sin novedades';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: appGlassDecoration(radius: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              member['name'] as String? ?? '',
              style: GoogleFonts.dmSans(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          Text(
            label,
            style: GoogleFonts.dmSans(
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.height = 54,
  });

  final String label;
  final VoidCallback onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.ink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(
        label,
        style: GoogleFonts.dmSans(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.body, this.when});

  final String body;
  final String? when;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: appGlassDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              body,
              style: GoogleFonts.dmSans(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
                height: 1.3,
              ),
            ),
            if (when != null) ...[
              const SizedBox(height: 6),
              Text(
                _friendlyTime(when!),
                style: GoogleFonts.dmSans(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _friendlyTime(String iso) {
  try {
    final dt = DateTime.parse(iso).toLocal();
    final now = DateTime.now();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final sameDay =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = dt.year == yesterday.year &&
        dt.month == yesterday.month &&
        dt.day == yesterday.day;
    if (sameDay) return 'Hoy $h:$m';
    if (isYesterday) return 'Ayer $h:$m';
    return '${dt.day}/${dt.month} $h:$m';
  } catch (_) {
    return '';
  }
}
