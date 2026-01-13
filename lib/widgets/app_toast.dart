import 'package:flutter/material.dart';

enum AppToastType { info, success, error }

class AppToast {
  static OverlayEntry? _currentEntry;
  
  static void show(BuildContext context, String message, {AppToastType type = AppToastType.info}) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final Color bgColor;
    final IconData icon;
    switch (type) {
      case AppToastType.success:
        bgColor = const Color(0xFF1DB954);
        icon = Icons.check_circle_outline;
        break;
      case AppToastType.error:
        bgColor = const Color(0xFFE53935);
        icon = Icons.error_outline;
        break;
      case AppToastType.info:
        bgColor = const Color(0xFF43A047);
        icon = Icons.info_outline;
        break;
    }

    // Ensure only one toast is visible at a time
    _currentEntry?.remove();

    final entry = OverlayEntry(
      builder: (context) => _DynamicIslandToast(
        message: message,
        backgroundColor: bgColor,
        icon: icon,
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);
  }
}

class _DynamicIslandToast extends StatefulWidget {
  final String message;
  final Color backgroundColor;
  final IconData icon;

  const _DynamicIslandToast({
    required this.message,
    required this.backgroundColor,
    required this.icon,
  });

  @override
  State<_DynamicIslandToast> createState() => _DynamicIslandToastState();
}

class _DynamicIslandToastState extends State<_DynamicIslandToast>
    with TickerProviderStateMixin {
  AnimationController? _slideController;
  AnimationController? _expandController;
  AnimationController? _fadeController;
  
  Animation<double>? _slideAnimation;
  Animation<double>? _expandAnimation;
  Animation<double>? _fadeAnimation;
  
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _initControllers();
    _startAnimation();
  }

  void _initControllers() {
    // Slide down animation (fast)
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    
    // Expand animation (smoother)
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    // Fade animation (slow)
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _slideAnimation = Tween<double>(
      begin: -120.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _slideController!,
      curve: Curves.elasticOut,
    ));

    _expandAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _expandController!,
      curve: Curves.easeOutQuart,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController!,
      curve: Curves.easeOut,
    ));
  }

  void _startAnimation() async {
    // Check if still mounted before each async operation
    if (_isDisposed || !mounted) return;
    
    // Phase 1: Symbol slides down
    _slideController?.forward();
    await Future.delayed(const Duration(milliseconds: 200));
    
    if (_isDisposed || !mounted) return;
    
    // Phase 2: Expand to show text
    _expandController?.forward();
    await Future.delayed(const Duration(milliseconds: 200));
    
    if (_isDisposed || !mounted) return;
    _fadeController?.forward();
    
    // Phase 3: Stay expanded for display duration
    await Future.delayed(const Duration(milliseconds: 2000));
    
    if (_isDisposed || !mounted) return;
    
    // Phase 4: Start exit animation
    await _exitAnimation();
  }

  Future<void> _exitAnimation() async {
    if (_isDisposed || !mounted) return;
    
    // Phase 1: Fade out text
    await _fadeController?.reverse();
    
    if (_isDisposed || !mounted) return;
    await Future.delayed(const Duration(milliseconds: 100));
    
    if (_isDisposed || !mounted) return;
    
    // Phase 2: Shrink back to symbol
    await _expandController?.reverse();
    
    if (_isDisposed || !mounted) return;
    await Future.delayed(const Duration(milliseconds: 300));
    
    if (_isDisposed || !mounted) return;
    
    // Phase 3: Slide up and disappear
    await _slideController?.reverse();
    
    // Remove from overlay
    if (mounted && !_isDisposed) {
      AppToast._currentEntry?.remove();
      AppToast._currentEntry = null;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _slideController?.dispose();
    _expandController?.dispose();
    _fadeController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Safety check for animations
    if (_slideAnimation == null || _expandAnimation == null || _fadeAnimation == null) {
      return const SizedBox.shrink();
    }
    
    return Positioned.fill(
      child: IgnorePointer(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _slideAnimation!,
                _expandAnimation!,
                _fadeAnimation!,
              ]),
              builder: (context, child) {
                final slideValue = _slideAnimation?.value ?? 0.0;
                final expandValue = _expandAnimation?.value ?? 0.0;
                final fadeValue = _fadeAnimation?.value ?? 0.0;
                
                return Transform.translate(
                  offset: Offset(0, slideValue),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 350),
                    margin: const EdgeInsets.only(top: 25),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      curve: Curves.easeOut,
                      padding: EdgeInsets.symmetric(
                        horizontal: 16 + (12 * expandValue),
                        vertical: 12 + (6 * expandValue),
                      ),
                      decoration: BoxDecoration(
                        color: widget.backgroundColor,
                        borderRadius: BorderRadius.circular(30 + (10 * expandValue)),
                        boxShadow: [
                          // White neon shadow
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.6 * fadeValue),
                            blurRadius: 8 + (4 * expandValue),
                            offset: const Offset(0, 2),
                            spreadRadius: 1,
                          ),
                          // Main shadow
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25 * fadeValue),
                            blurRadius: 25 + (10 * expandValue),
                            offset: Offset(0, 10 + (5 * expandValue)),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Icon - always visible
                          Icon(
                            widget.icon,
                            color: Colors.white,
                            size: 22,
                          ),
                          
                          // Text - only visible when expanded
                          if (expandValue > 0.3) ...[
                            SizedBox(width: 10 + (5 * expandValue)),
                            Flexible(
                              child: AnimatedOpacity(
                                opacity: expandValue > 0.5 ? fadeValue : 0.0,
                                duration: const Duration(milliseconds: 200),
                                child: DefaultTextStyle(
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.none,
                                  ),
                                  child: Text(
                                    widget.message,
                                    maxLines: 3,
                                    overflow: TextOverflow.visible,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
