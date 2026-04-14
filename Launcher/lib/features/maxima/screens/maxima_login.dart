import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'package:grpc/grpc.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/features/maxima/providers/maxima_cubit.dart';
import 'package:kyber_launcher/features/patreon/services/patreon_service.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/injection_container.dart' show isLanMode;
import 'package:kyber_launcher/shared/ui/buttons/button.dart';
import 'package:kyber_launcher/shared/ui/elements/kyber_input.dart';
import 'package:kyber_launcher/shared/ui/utils/background_blur.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';

class MaximaLogin extends StatefulWidget {
  const MaximaLogin({super.key});

  @override
  State<MaximaLogin> createState() => _MaximaLoginState();
}

class _MaximaLoginState extends State<MaximaLogin> {
  static const _boxConstraints = BoxConstraints(
    maxWidth: 700,
    minWidth: 700,
    minHeight: 100,
  );

  bool _whitelistPrompt = false;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        LogicalKeySet(
          .control,
          .shift,
          .alt,
        ): _toggleFrbDebugLogs,
      },
      child: Focus(
        autofocus: true,
        child: Center(
          child: ConstrainedBox(
            constraints: _boxConstraints,
            child: ClipRRect(
              borderRadius: .circular(kDefaultOuterBorderRadius),
              child: BackgroundBlur(
                child: Container(
                  constraints: _boxConstraints,
                  decoration: BoxDecoration(
                    border: kDefaultAllBorder,
                    borderRadius: .circular(
                      kDefaultOuterBorderRadius,
                    ),
                  ),
                  padding: kDefaultPadding,
                  child: Column(
                    mainAxisSize: .min,
                    crossAxisAlignment: .start,
                    children: [
                      _Header(),
                      BlocBuilder<MaximaCubit, MaximaState>(
                        builder: _buildContent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toggleFrbDebugLogs() {
    Preferences.debug.frbDebugLogs = !Preferences.debug.frbDebugLogs;
    NotificationService.info(
      message:
          '${Preferences.debug.frbDebugLogs ? 'Enabled' : 'Disabled'} debug logs',
    );
  }

  Widget _buildContent(BuildContext context, MaximaState state) {
    if (_loading) {
      return _StatusRow(
        text: _whitelistPrompt ? 'Loading...' : 'Waiting for response...',
      );
    }

    if (_whitelistPrompt) {
      return _WhitelistPrompt(
        displayName: state.servicePlayer?.displayName,
        onLogout: () => context.read<MaximaCubit>().logout(),
        onAddToWhitelist: () => _handleAddToWhitelist(context),
      );
    }

    final errorBlock = _buildErrorBlock(context, state);
    if (errorBlock != null) return errorBlock;

    if (isLanMode) {
      return switch (state.status) {
        .loading => const _StatusRow(text: 'Connecting...'),
        _ => _LanLoginForm(
            onLogin: (username) =>
                context.read<MaximaCubit>().requestLanLogin(username),
          ),
      };
    }

    return switch (state.status) {
      .starting => const _StatusRow(text: 'Maxima is starting...'),
      .loading => const _StatusRow(text: 'Fetching data...'),
      _ => _LoginIntro(onLogin: () => _requestLogin(context)),
    };
  }

  Widget? _buildErrorBlock(BuildContext context, MaximaState state) {
    if (state.status != MaximaStatus.error) return null;

    final error = state.error ?? 'An error occurred';

    if (error.contains('GameNotOwned')) {
      return _GameNotOwned(
        eaId: state.servicePlayer?.uniqueName,
        onLogout: () => context.read<MaximaCubit>().logout(),
      );
    }

    if (error.contains('whitelist')) {
      return _WhitelistRequired(
        eaId: state.servicePlayer?.uniqueName,
        onLogout: () => context.read<MaximaCubit>().logout(),
        onAuthorizePatreon: () => _handleAuthorizePatreon(context),
      );
    }

    return _MaximaGenericError(
      error: error,
      onCopyPath: () => _copyPath(context),
      onLogout: () => context.read<MaximaCubit>().logout(),
    );
  }

  Future<void> _requestLogin(BuildContext context) {
    return context.read<MaximaCubit>().requestLogin().onError((
      error,
      stackTrace,
    ) {
      if (error is! PanicException && error! is AnyhowException) return;

      final raw = error is PanicException
          ? error.message
          : (error! as AnyhowException).message;

      final message = _mapLoginError(raw);

      return NotificationService.showNotification(
        title: 'Login failed',
        message: message,
        severity: InfoBarSeverity.error,
      );
    });
  }

  String _mapLoginError(String err) {
    if (err.contains('unknown variant `NO_SUCH_USER`')) {
      return 'The specified user does not exist';
    }

    if (err.contains('InvalidPassword')) {
      return 'The specified password is incorrect';
    }

    if (err.contains('failed to find auth code')) {
      return 'Failed to find auth code. Please try another browser';
    }

    return err;
  }

  void _copyPath(BuildContext context) {
    Clipboard.setData(ClipboardData(text: Directory.current.path));
    NotificationService.success(
      message: 'The path has been copied to your clipboard',
    );
  }

  Future<void> _handleAuthorizePatreon(BuildContext context) async {
    try {
      setState(() => _loading = true);

      final code = await PatreonService.requestOAuthLogin();
      if (code == null) {
        NotificationService.error(
          message: 'No authorization code was received',
        );
        return;
      }

      await PatreonService.fetchToken(code);

      if (!mounted) return;
      setState(() {
        _whitelistPrompt = true;
        _loading = false;
      });

      NotificationService.success(
        title: 'Authorization successful',
        message: 'You have been successfully authorized as a Patreon member',
      );
    } catch (e, s) {
      String? message;
      if (e is GrpcError) message = e.message;
      if (e is PatreonException) message = e.message;

      Logger.root.warning('Failed to authorize Patreon', e, s);

      NotificationService.showNotification(
        title: 'Authorization failed',
        message: message ?? e.toString(),
        severity: InfoBarSeverity.error,
      );
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _handleAddToWhitelist(BuildContext context) async {
    setState(() => _loading = true);
    try {
      await PatreonService.addToWhitelist();
      await Future.delayed(const Duration(milliseconds: 200));

      await context.read<MaximaCubit>().requestLogin(skipMaximaCheck: true);
    } catch (e, s) {
      final message = switch (e) {
        GrpcError() => e.message ?? 'An error occurred',
        PatreonException() => e.message,
        _ => e.toString(),
      };

      Logger.root.warning('Failed to add to whitelist', e, s);
      NotificationService.error(message: message);
      context.read<MaximaCubit>().emitError(message);
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      isLanMode ? 'LAN Login' : 'EA Login',
      style: FluentTheme.of(context).typography.subtitle?.copyWith(
        fontFamily: FontFamily.battlefrontUI,
        fontSize: 26,
        color: kActiveColor,
        shadows: [
          Shadow(
            color: kActiveColor.withOpacity(0.25),
            offset: const Offset(0, 1),
            blurRadius: 20,
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      children: [
        const SizedBox(height: 5),
        Row(
          children: [
            const SizedBox(height: 20, width: 20, child: ProgressRing()),
            const SizedBox(width: 8),
            Text(
              text,
              style: const TextStyle(
                fontFamily: FontFamily.battlefrontUI,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LoginIntro extends StatelessWidget {
  const _LoginIntro({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: [
        Text(
          'In order to use this launcher, you need to login to Maxima. This is required to launch and interact with Battlefront 2.\nYou will be redirected to the EA login page and after logging in, you will be redirected back to the launcher.',
          style: FluentTheme.of(context).typography.body,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            KyberButton(
              text: 'Login with EA',
              onPressed: onLogin,
            ),
          ],
        ),
      ],
    );
  }
}

class _WhitelistRequired extends StatelessWidget {
  const _WhitelistRequired({
    required this.eaId,
    required this.onLogout,
    required this.onAuthorizePatreon,
  });

  final String? eaId;
  final VoidCallback onLogout;
  final Future<void> Function() onAuthorizePatreon;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: [
        DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 16),
          child: Row(children: [Text('EA-ID: $eaId')]),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: .spaceBetween,
          children: [
            KyberButton(text: 'Log out', onPressed: onLogout),
            KyberButton(
              text: 'Authorize Patreon',
              onPressed: onAuthorizePatreon,
            ),
          ],
        ),
      ],
    );
  }
}

class _WhitelistPrompt extends StatelessWidget {
  const _WhitelistPrompt({
    required this.displayName,
    required this.onLogout,
    required this.onAddToWhitelist,
  });

  final String? displayName;
  final VoidCallback onLogout;
  final Future<void> Function() onAddToWhitelist;

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: const TextStyle(fontSize: 16),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          const Text(
            'Are you sure you want to add your current account to the whitelist?',
          ),
          const SizedBox(height: 10),
          Text('Current account: $displayName'),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: .spaceBetween,
            children: [
              KyberButton(text: 'Log out', onPressed: onLogout),
              KyberButton(
                text: 'Add to whitelist',
                onPressed: onAddToWhitelist,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GameNotOwned extends StatelessWidget {
  const _GameNotOwned({required this.eaId, required this.onLogout});

  final String? eaId;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        DefaultTextStyle.merge(
          style: const .new(fontSize: 16),
          child: Row(children: [Text('EA-ID: $eaId')]),
        ),
        const SizedBox(height: 10),
        const Text(
          'It seems like you do not own Battlefront 2. Please purchase the game or use another account.',
        ),
        const SizedBox(height: 10),
        Row(
          children: [KyberButton(text: 'Log out', onPressed: onLogout)],
        ),
      ],
    );
  }
}

class _MaximaGenericError extends StatelessWidget {
  const _MaximaGenericError({
    required this.error,
    required this.onCopyPath,
    required this.onLogout,
  });

  final String error;
  final VoidCallback onCopyPath;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final bodyStyle = FluentTheme.of(
      context,
    ).typography.body?.copyWith(fontSize: 16);

    return DefaultTextStyle.merge(
      style: bodyStyle,
      child: Column(
        children: [
          Builder(
            builder: (context) {
              switch (error) {
                case 'MaximaFailedBackgroundService':
                  return const Text(
                    'Maxima failed to start the background service. This is usually caused by an antivirus program blocking the service. Please add an exception for the launcher and reinstall it.',
                  );
                case 'MissingMaximaFiles':
                  return Column(
                    crossAxisAlignment: .start,
                    children: [
                      const Text(
                        'Some files required to run Maxima are missing. This is usually caused by an antivirus program deleting the files. Please add an exception for the launcher and reinstall it.',
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "Please exclude the following folders from your antivirus' real-time protection:",
                      ),
                      const SizedBox(height: 5),
                      KyberInput(
                        initialValue: dirname(Platform.resolvedExecutable),
                        disabled: true,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: .spaceBetween,
                        children: [
                          KyberButton(text: 'COPY PATH', onPressed: onCopyPath),
                        ],
                      ),
                    ],
                  );
                default:
                  return Text(error);
              }
            },
          ),
          Row(
            children: [KyberButton(text: 'Log out', onPressed: onLogout)],
          ),
        ],
      ),
    );
  }
}

class _LanLoginForm extends StatefulWidget {
  const _LanLoginForm({required this.onLogin});

  final void Function(String username) onLogin;

  @override
  State<_LanLoginForm> createState() => _LanLoginFormState();
}

class _LanLoginFormState extends State<_LanLoginForm> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) {
      widget.onLogin(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter your player name to join the LAN party.',
          style: FluentTheme.of(context).typography.body,
        ),
        const SizedBox(height: 12),
        TextBox(
          controller: _controller,
          placeholder: 'Player name',
          onSubmitted: (_) => _submit(),
          autofocus: true,
          style: const TextStyle(
            fontFamily: FontFamily.battlefrontUI,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            KyberButton(
              text: 'Join LAN',
              onPressed: _submit,
            ),
          ],
        ),
      ],
    );
  }
}

class MaximaErrorWidget extends StatelessWidget {
  const MaximaErrorWidget({required this.state, super.key});

  final MaximaState state;

  @override
  Widget build(BuildContext context) {
    final error = state.error ?? '';

    if (error.contains('GameNotOwned')) {
      return _GameNotOwned(
        eaId: state.servicePlayer?.uniqueName,
        onLogout: () => context.read<MaximaCubit>().logout(),
      );
    }

    if (state.status == MaximaStatus.error && !error.contains('whitelist')) {
      return _MaximaGenericError(
        error: error.isEmpty ? 'An error occurred' : error,
        onLogout: () => context.read<MaximaCubit>().logout(),
        onCopyPath: () async {
          await Clipboard.setData(.new(text: Directory.current.path));

          if (!context.mounted) return;

          NotificationService.success(
            message: 'The path has been copied to your clipboard',
          );
        },
      );
    }

    return const SizedBox.shrink();
  }
}
