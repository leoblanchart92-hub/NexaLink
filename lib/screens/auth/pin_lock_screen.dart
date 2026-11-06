import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../services/biometric_service.dart';

/// PIN lock screen - displayed when biometric auth is enabled
class PinLockScreen extends StatefulWidget {
  final bool isVerify; // true = verify existing PIN, false = set new PIN

  const PinLockScreen({super.key, this.isVerify = true});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> with TickerProviderStateMixin {
  final List<String> _enteredPin = [];
  late BiometricService _biometricService;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  bool _isVerifying = false;
  bool _serviceReady = false;
  String _errorText = '';
  int _lockoutSeconds = 0;
  Timer? _lockoutTimer;
  
  // For new PIN setup
  String? _firstPinEntry;
  bool _isConfirmStep = false;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
    _initService();
  }

  Future<void> _initService() async {
    _biometricService = await BiometricService.getInstance();
    if (widget.isVerify && _biometricService.isLockedOut()) {
      _startLockoutTimer();
    }
    if (mounted) {
      setState(() => _serviceReady = true);
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  void _startLockoutTimer() {
    _lockoutSeconds = _biometricService.getRemainingLockoutSeconds();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _lockoutSeconds = _biometricService.getRemainingLockoutSeconds();
      if (_lockoutSeconds <= 0) {
        timer.cancel();
        setState(() {});
      } else {
        setState(() {});
      }
    });
  }

  void _onKeyPressed(String key) {
    if (_lockoutSeconds > 0) return;
    if (_enteredPin.length >= 6) return;

    setState(() {
      _enteredPin.add(key);
      _errorText = '';
    });

    HapticFeedback.lightImpact();

    if (_enteredPin.length == 6) {
      _verifyPin();
    }
  }

  void _onDeletePressed() {
    if (_enteredPin.isEmpty) return;
    setState(() {
      _enteredPin.removeLast();
      _errorText = '';
    });
  }

  Future<void> _verifyPin() async {
    final pin = _enteredPin.join();

    if (!widget.isVerify) {
      // Setting new PIN
      if (!_isConfirmStep) {
        _firstPinEntry = pin;
        setState(() {
          _isConfirmStep = true;
          _enteredPin.clear();
        });
        return;
      } else {
        if (pin == _firstPinEntry) {
          await _biometricService.setPin(pin);
          await _biometricService.setPinLockEnabled(true);
          if (mounted) {
            Navigator.of(context).pop(true);
          }
        } else {
          setState(() {
            _errorText = 'Les codes ne correspondent pas';
            _enteredPin.clear();
            _isConfirmStep = false;
            _firstPinEntry = null;
          });
          _shakeController.forward(from: 0);
        }
        return;
      }
    }

    // Verify existing PIN
    setState(() => _isVerifying = true);

    await Future.delayed(const Duration(milliseconds: 300));

    if (_biometricService.verifyPin(pin)) {
      await _biometricService.resetFailedAttempts();
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(AppRoutes.home);
      }
    } else {
      await _biometricService.recordFailedAttempt();
      
      setState(() {
        _enteredPin.clear();
        _isVerifying = false;
        _errorText = 'Code incorrect';
      });

      _shakeController.forward(from: 0);

      if (_biometricService.isLockedOut()) {
        _startLockoutTimer();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_serviceReady) {
      return const Scaffold(
        backgroundColor: NexaLinkTheme.darkBackground,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: NexaLinkTheme.darkBackground,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),

            // Lock icon
            _AnimatedShake(
              animation: _shakeAnimation,
              controller: _shakeController,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: _biometricService.isLockedOut()
                      ? null
                      : NexaLinkTheme.primaryGradient,
                  color: _biometricService.isLockedOut()
                      ? NexaLinkTheme.error.withOpacity(0.2)
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: NexaLinkTheme.electricBlue.withOpacity(0.3),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(
                  _biometricService.isLockedOut()
                      ? Icons.lock_clock_rounded
                      : Icons.lock_rounded,
                  size: 40,
                  color: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Title
            Text(
              widget.isVerify
                  ? (_isVerifying ? 'Vérification...' : 'Code PIN')
                  : (_isConfirmStep ? 'Confirmez le code' : 'Entrer un code PIN'),
              style: const TextStyle(
                color: NexaLinkTheme.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 8),

            // Subtitle / Error
            if (_lockoutSeconds > 0)
              Text(
                'Trop de tentatives. Réessayez dans $_lockoutSeconds s',
                style: const TextStyle(
                  color: NexaLinkTheme.error,
                  fontSize: 13,
                ),
              )
            else if (_errorText.isNotEmpty)
              Text(
                _errorText,
                style: const TextStyle(
                  color: NexaLinkTheme.error,
                  fontSize: 13,
                ),
              )
            else
              Text(
                widget.isVerify
                    ? 'Entrez votre code PIN à 6 chiffres'
                    : 'Choisissez un code à 6 chiffres',
                style: const TextStyle(
                  color: NexaLinkTheme.textMuted,
                  fontSize: 13,
                ),
              ),

            const SizedBox(height: 32),

            // PIN dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (index) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index < _enteredPin.length
                        ? NexaLinkTheme.electricBlue
                        : Colors.transparent,
                    border: Border.all(
                      color: index < _enteredPin.length
                          ? NexaLinkTheme.electricBlue
                          : NexaLinkTheme.textMuted.withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                );
              }),
            ),

            const Spacer(),

            // Number pad
            _buildNumberPad(),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberPad() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        children: [
          // Row 1: 1, 2, 3
          _buildNumberRow(['1', '2', '3']),
          const SizedBox(height: 16),
          // Row 2: 4, 5, 6
          _buildNumberRow(['4', '5', '6']),
          const SizedBox(height: 16),
          // Row 3: 7, 8, 9
          _buildNumberRow(['7', '8', '9']),
          const SizedBox(height: 16),
          // Row 4: empty, 0, delete
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(width: 72),
              _buildNumberKey('0'),
              _buildDeleteKey(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNumberRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map((key) => _buildNumberKey(key)).toList(),
    );
  }

  Widget _buildNumberKey(String key) {
    return GestureDetector(
      onTap: () => _onKeyPressed(key),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: NexaLinkTheme.surfaceCard,
        ),
        child: Center(
          child: Text(
            key,
            style: const TextStyle(
              color: NexaLinkTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeleteKey() {
    return GestureDetector(
      onTap: _onDeletePressed,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: NexaLinkTheme.surfaceCard,
        ),
        child: const Icon(
          Icons.backspace_rounded,
          color: NexaLinkTheme.textSecondary,
          size: 24,
        ),
      ),
    );
  }
}

/// Shake animation widget
class _AnimatedShake extends StatefulWidget {
  final Animation<double> animation;
  final AnimationController controller;
  final Widget child;

  const _AnimatedShake({
    required this.animation,
    required this.controller,
    required this.child,
  });

  @override
  State<_AnimatedShake> createState() => _AnimatedShakeState();
}

class _AnimatedShakeState extends State<_AnimatedShake> {
  @override
  void initState() {
    super.initState();
    widget.animation.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final shakeOffset = widget.controller.isAnimating
        ? widget.animation.value * 10 *
            (widget.controller.value < 0.5 ? 1 : -1)
        : 0.0;
    return Transform.translate(
      offset: Offset(shakeOffset, 0),
      child: widget.child,
    );
  }
}
