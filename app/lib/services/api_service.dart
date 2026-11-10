import '../models/announcement.dart';
import '../models/auth.dart';
import '../models/church.dart';
import '../models/contribution.dart';
import '../models/member.dart';
import '../models/rapport.dart';
import '../models/rattachement.dart';

/// Erreur renvoyée par l'API (ou par le service en mode démo).
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

/// Interface unique parlée par les écrans. Deux implémentations :
/// [HttpApiService] (API réelle) et [MockApiService] (mode démo, données
/// « Grâce Divine » en mémoire). Les écrans ne connaissent que cette interface.
abstract class ApiService {
  // -- Authentification -----------------------------------------------------
  Future<AuthResult> login({required String email, required String password});

  Future<AuthResult> register({
    required String churchName,
    required String city,
    String? churchPhone,
    String? churchEmail,
    required String adminName,
    required String adminEmail,
    required String password,
    String? parentCode,
  });

  Future<MeResult> me();

  // -- Églises et arborescence ----------------------------------------------
  Future<TreeResult> getTree();

  Future<Church> createSubChurch({
    required String name,
    required String city,
    String? phone,
    String? email,
  });

  // -- Rattachements ---------------------------------------------------------
  Future<RattachementsResult> getRattachements();

  Future<Rattachement> requestRattachement({required String parentCode});

  Future<void> decideRattachement(String id, {required bool accept});

  // -- Membres ---------------------------------------------------------------
  Future<MemberPage> getMembers({String? q, String? department, String? status});

  Future<Member> getMember(String id);

  Future<Member> createMember({
    required String fullName,
    String? phone,
    String? email,
    String? birthDate,
    String? department,
    String? cellGroup,
    String? status,
  });

  // -- Finances --------------------------------------------------------------
  Future<ContributionPage> getContributions({String? type, String? status});

  Future<Contribution> getReceipt(String id);

  Future<Contribution> createContribution({
    required String type,
    required int amountFcfa,
    required String paymentMethod,
    String? paymentRef,
    String? memberId,
    String? note,
  });

  Future<Contribution> setContributionStatus(String id, String status);

  // -- Rapports et annonces --------------------------------------------------
  Future<RapportConsolide> getRapport();

  Future<List<Announcement>> getAnnonces();

  Future<Announcement> createAnnonce({
    required String title,
    required String body,
    required bool broadcast,
  });
}
