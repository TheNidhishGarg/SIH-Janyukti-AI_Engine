import 'package:flutter/material.dart';

enum AppLanguage { english, hindi, nagpuri }

class LanguageController extends ChangeNotifier {
  AppLanguage language = AppLanguage.english;
  void select(AppLanguage value) {
    language = value;
    notifyListeners();
  }
}

class LanguageScope extends InheritedNotifier<LanguageController> {
  const LanguageScope({
    super.key,
    required LanguageController controller,
    required super.child,
  }) : super(notifier: controller);
  static LanguageController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LanguageScope>()!.notifier!;
}

String tr(BuildContext context, String value) {
  final language = LanguageScope.of(context).language;
  if (language == AppLanguage.english) return value;
  return (_copy[language]?[value] ?? value);
}

String languageName(AppLanguage language) => switch (language) {
  AppLanguage.english => 'English',
  AppLanguage.hindi => 'हिंदी',
  AppLanguage.nagpuri => 'Nagpuri',
};

const _copy = <AppLanguage, Map<String, String>>{
  AppLanguage.hindi: {
    'Welcome to janYukti': 'janYukti में आपका स्वागत है',
    'Choose how you want to continue': 'आगे बढ़ने का तरीका चुनें',
    'Citizen': 'नागरिक',
    'University': 'विश्वविद्यालय',
    'Industry': 'उद्योग',
    'Administrator': 'प्रशासक',
    'Report and track public issues': 'जनसमस्याओं की रिपोर्ट और ट्रैक करें',
    'Solve real-world challenges': 'वास्तविक चुनौतियों को हल करें',
    'Collaborate and provide solutions': 'सहयोग करें और समाधान दें',
    'Manage the janYukti ecosystem': 'janYukti इकोसिस्टम प्रबंधित करें',
    'Password': 'पासवर्ड',
    'Forgot Password?': 'पासवर्ड भूल गए?',
    'Choose another role': 'दूसरी भूमिका चुनें',
    'Not a ': 'आप ',
    'Login as Citizen': 'नागरिक के रूप में लॉगिन',
    'Login as University': 'विश्वविद्यालय के रूप में लॉगिन',
    'Login as Industry': 'उद्योग के रूप में लॉगिन',
    'Secure Login': 'सुरक्षित लॉगिन',
    'Citizen Portal': 'नागरिक पोर्टल',
    'University Portal': 'विश्वविद्यालय पोर्टल',
    'Industry Portal': 'उद्योग पोर्टल',
    'Administrator Portal': 'प्रशासक पोर्टल',
    'Citizen Dashboard': 'नागरिक डैशबोर्ड',
    'University Dashboard': 'विश्वविद्यालय डैशबोर्ड',
    'Industry Dashboard': 'उद्योग डैशबोर्ड',
    'Admin Dashboard': 'प्रशासक डैशबोर्ड',
    'Recent Challenges': 'हाल की चुनौतियाँ',
    'Recent Assigned Challenges': 'हाल में सौंपी गई चुनौतियाँ',
    'Recommended Projects': 'अनुशंसित प्रोजेक्ट',
    'Challenges Assigned': 'सौंपी गई चुनौतियाँ',
    'Projects in Progress': 'प्रगति पर प्रोजेक्ट',
    'Opportunities': 'अवसर',
    'Collaborations': 'सहयोग',
    'Report a Challenge': 'चुनौती रिपोर्ट करें',
    'My Challenges': 'मेरी चुनौतियाँ',
    'Challenges': 'चुनौतियाँ',
    'In Progress': 'प्रगति पर',
    'People Impacted': 'लाभान्वित लोग',
    'Submit Challenge': 'चुनौती जमा करें',
    'Track Challenge': 'चुनौती ट्रैक करें',
    'Challenge Details': 'चुनौती विवरण',
    'Assign Challenge': 'चुनौती सौंपें',
    'Project Workspace': 'प्रोजेक्ट कार्यक्षेत्र',
    'Project Details': 'प्रोजेक्ट विवरण',
    'Express Interest': 'रुचि व्यक्त करें',
    'My Collaborations': 'मेरे सहयोग',
    'Collaboration Chat': 'सहयोग चैट',
    'Analytics Dashboard': 'एनालिटिक्स डैशबोर्ड',
    'Project Monitoring': 'प्रोजेक्ट मॉनिटरिंग',
    'Water Management': 'जल प्रबंधन',
    'Waste Management': 'कचरा प्रबंधन',
    'Education': 'शिक्षा',
    'High': 'उच्च',
    'Medium': 'मध्यम',
  },
  AppLanguage.nagpuri: {
    'Welcome to janYukti': 'janYukti में राउर स्वागत हे',
    'Choose how you want to continue': 'आगे कइसन बढ़े के हे, चुनू',
    'Citizen': 'नागरिक',
    'University': 'विश्वविद्यालय',
    'Industry': 'उद्योग',
    'Administrator': 'प्रशासक',
    'Report and track public issues': 'जन समस्या के रिपोर्ट आउर ट्रैक करू',
    'Solve real-world challenges': 'असल दुनिया के चुनौती सुलझाऊ',
    'Collaborate and provide solutions': 'मिल-जुल के समाधान देवू',
    'Manage the janYukti ecosystem': 'janYukti व्यवस्था के संभालू',
    'Password': 'पासवर्ड',
    'Forgot Password?': 'पासवर्ड भूला गेलें?',
    'Choose another role': 'दोसर भूमिका चुनू',
    'Login as Citizen': 'नागरिक बनके लॉगिन',
    'Login as University': 'विश्वविद्यालय बनके लॉगिन',
    'Login as Industry': 'उद्योग बनके लॉगिन',
    'Secure Login': 'सुरक्षित लॉगिन',
    'Citizen Portal': 'नागरिक पोर्टल',
    'University Portal': 'विश्वविद्यालय पोर्टल',
    'Industry Portal': 'उद्योग पोर्टल',
    'Administrator Portal': 'प्रशासक पोर्टल',
    'Citizen Dashboard': 'नागरिक डैशबोर्ड',
    'University Dashboard': 'विश्वविद्यालय डैशबोर्ड',
    'Industry Dashboard': 'उद्योग डैशबोर्ड',
    'Admin Dashboard': 'प्रशासक डैशबोर्ड',
    'Recent Challenges': 'हाल के चुनौती',
    'Recent Assigned Challenges': 'हाल में मिलल चुनौती',
    'Recommended Projects': 'सुझावल प्रोजेक्ट',
    'Challenges Assigned': 'मिलल चुनौती',
    'Projects in Progress': 'चलत प्रोजेक्ट',
    'Opportunities': 'मौका',
    'Collaborations': 'सहयोग',
    'Report a Challenge': 'चुनौती रिपोर्ट करू',
    'My Challenges': 'मोर चुनौती',
    'Challenges': 'चुनौती',
    'In Progress': 'चलत हे',
    'People Impacted': 'लाभ पावल लोग',
    'Submit Challenge': 'चुनौती जमा करू',
    'Track Challenge': 'चुनौती ट्रैक करू',
    'Challenge Details': 'चुनौती विवरण',
    'Assign Challenge': 'चुनौती सौंपू',
    'Project Workspace': 'प्रोजेक्ट काम-जगह',
    'Project Details': 'प्रोजेक्ट विवरण',
    'Express Interest': 'रुचि देखाऊ',
    'My Collaborations': 'मोर सहयोग',
    'Collaboration Chat': 'सहयोग बात-चीत',
    'Analytics Dashboard': 'आँकड़ा डैशबोर्ड',
    'Project Monitoring': 'प्रोजेक्ट निगरानी',
    'Water Management': 'पानी प्रबंधन',
    'Waste Management': 'कचरा प्रबंधन',
    'Education': 'शिक्षा',
    'High': 'बेसी',
    'Medium': 'मध्यम',
  },
};
