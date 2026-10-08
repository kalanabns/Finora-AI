import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/finora_error_view.dart';
import '../../alerts/domain/alert.dart';
import '../../businesses/domain/business.dart';
import '../../financial_health/domain/financial_metric.dart';
import '../../transactions/domain/transaction.dart';
import '../application/ai_cfo_controller.dart';
import '../domain/ai_conversation.dart';

class AICFOScreen extends StatefulWidget {
  const AICFOScreen({
    super.key,
    required this.controller,
    required this.business,
    this.currentMetrics,
    this.activeAlerts,
    this.recentTransactions,
    this.initialAlertToExplain,
  });

  final AICFOController controller;
  final Business business;
  final FinancialMetric? currentMetrics;
  final List<Alert>? activeAlerts;
  final List<Transaction>? recentTransactions;
  final Alert? initialAlertToExplain;

  @override
  State<AICFOScreen> createState() => _AICFOScreenState();
}

class _AICFOScreenState extends State<AICFOScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _hasSentInitialAlert = false;

  static const List<String> _quickPrompts = [
    'How is my business doing this month?',
    'What is my biggest financial risk?',
    'Where can I reduce expenses?',
    'Can I afford to hire new staff?',
    'How much cash will I have next month?',
    'What happens if I increase prices by 5%?',
    'Why did my profit margin change?',
    'What strategic action should I prioritize?',
    'Are there any revenue opportunities I am missing?',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialAlertToExplain != null && !_hasSentInitialAlert) {
        _hasSentInitialAlert = true;
        _sendAlertExplanation(widget.initialAlertToExplain!);
      } else if (widget.controller.messages.isEmpty) {
        _handleSend('What happens if I increase prices by 5%?');
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSend([String? textOverride]) async {
    final query = textOverride ?? _textController.text;
    if (query.trim().isEmpty) return;

    _textController.clear();
    FocusScope.of(context).unfocus();

    await widget.controller.sendMessage(
      message: query,
      businessId: widget.business.id,
      currentMetrics: widget.currentMetrics,
      business: widget.business,
      activeAlerts: widget.activeAlerts,
      recentTransactions: widget.recentTransactions,
    );

    _scrollToBottom();
  }

  Future<void> _sendAlertExplanation(Alert alert) async {
    await widget.controller.sendMessage(
      message:
          'Explain this signal: "${alert.title}" and provide practical next steps.',
      businessId: widget.business.id,
      alertContext: alert,
      currentMetrics: widget.currentMetrics,
      business: widget.business,
      activeAlerts: widget.activeAlerts,
      recentTransactions: widget.recentTransactions,
    );
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final messages = widget.controller.messages;
        final isLoading = widget.controller.isLoading;
        final error = widget.controller.errorMessage;

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: Column(
            children: [
              // 40% Navy Header & Advisor Context
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                decoration: const BoxDecoration(
                  color: AppTheme.surface,
                  border: Border(
                    bottom: BorderSide(color: AppTheme.borderColor),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryNavy,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.psychology_rounded,
                        color: AppTheme.primaryLight,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Text(
                                'Finora AI CFO',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              SizedBox(width: 6),
                              Icon(
                                Icons.verified_rounded,
                                size: 14,
                                color: AppTheme.primaryColor,
                              ),
                            ],
                          ),
                          Text(
                            'Grounded in ${widget.business.name} metrics (${widget.business.currency})',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      tooltip: 'New Conversation Session',
                      color: AppTheme.textSecondary,
                      onPressed: () =>
                          widget.controller.resetSession(widget.business.id),
                    ),
                  ],
                ),
              ),

              // Chat Message List (60% White / Light Canvas)
              Expanded(
                child: messages.isEmpty
                    ? _buildWelcomeState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16.0),
                        itemCount: messages.length + (isLoading ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == messages.length && isLoading) {
                            return _buildTypingIndicator();
                          }
                          final msg = messages[index];
                          return _buildMessageBubble(msg);
                        },
                      ),
              ),

              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 4,
                  ),
                  child: FinoraErrorView(
                    message: error,
                    onRetry: () =>
                        widget.controller.resetSession(widget.business.id),
                  ),
                ),

              // Quick Prompts Carousel (when message history is small)
              if (messages.length <= 2 && !isLoading)
                Container(
                  height: 42,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: _quickPrompts.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final prompt = _quickPrompts[i];
                      return ActionChip(
                        label: Text(
                          prompt,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.primaryNavy,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        backgroundColor: AppTheme.surface,
                        side: const BorderSide(color: AppTheme.borderColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        onPressed: () => _handleSend(prompt),
                      );
                    },
                  ),
                ),

              // Input Bar (Crisp White with Soft Border)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                decoration: const BoxDecoration(
                  color: AppTheme.surface,
                  border: Border(top: BorderSide(color: AppTheme.borderColor)),
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _handleSend(),
                          decoration: InputDecoration(
                            hintText:
                                'Ask Finora AI CFO about your finances...',
                            hintStyle: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.textMuted,
                            ),
                            fillColor: AppTheme.surfaceElevated,
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: const BorderSide(
                                color: AppTheme.borderColor,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: const BorderSide(
                                color: AppTheme.borderColor,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: const BorderSide(
                                color: AppTheme.primaryColor,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: const BoxDecoration(
                          color: AppTheme.primaryNavy,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(
                            Icons.arrow_upward_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: isLoading ? null : () => _handleSend(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWelcomeState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.psychology_rounded,
                    size: 28,
                    color: AppTheme.primaryLight,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Meet Your Finora AI CFO',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Executive financial guidance grounded directly in your verified business transactions and health metrics.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Suggested Inquiries',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ..._quickPrompts.map(
            (p) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                tileColor: AppTheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppTheme.borderColor),
                ),
                leading: const Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: AppTheme.primaryColor,
                  size: 20,
                ),
                title: Text(
                  p,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: AppTheme.textMuted,
                ),
                onTap: () => _handleSend(p),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(AIConversation message) {
    final isUser = message.role == AIRole.user;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: AppTheme.primaryNavy,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.psychology_rounded,
                size: 16,
                color: AppTheme.primaryLight,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: isUser ? AppTheme.primaryColor : AppTheme.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: isUser ? null : Border.all(color: AppTheme.borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: isUser
                  ? Text(
                      message.message,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  : _buildFormattedAssistantContent(message.message),
            ),
          ),
          if (isUser) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildFormattedAssistantContent(String text) {
    // Simple markdown header parser for structured sections
    final lines = text.split('\n');
    final widgets = <Widget>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('### ') || trimmed.startsWith('## ')) {
        final heading = trimmed.replaceAll(RegExp(r'^#+\s*'), '');
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
            child: Text(
              heading.toUpperCase(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryNavy,
                letterSpacing: 0.4,
              ),
            ),
          ),
        );
      } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                Expanded(
                  child: Text(
                    trimmed.substring(2),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (trimmed.isNotEmpty) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Text(
              trimmed,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppTheme.textPrimary,
                height: 1.45,
              ),
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: AppTheme.primaryNavy,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.psychology_rounded,
              size: 16,
              color: AppTheme.primaryLight,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderColor),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppTheme.primaryColor,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'Finora AI CFO is analyzing...',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
