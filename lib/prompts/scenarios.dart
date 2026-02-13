import '../models/scenario.dart';

const List<Scenario> defaultScenarios = [
  Scenario(
    id: 'free_talk',
    title: 'Free Talk',
    description: 'Just chat freely about anything',
    icon: '💬',
    systemPromptAddition: '',
  ),
  Scenario(
    id: 'coffee_shop',
    title: 'Coffee Shop',
    description: 'Order drinks and chat with a barista',
    icon: '☕',
    systemPromptAddition:
        'You are also role-playing as a friendly barista at a coffee shop. '
        'Start by greeting the user and asking what they\'d like to order. '
        'Make small talk while preparing their order.',
  ),
  Scenario(
    id: 'job_interview',
    title: 'Job Interview',
    description: 'Practice answering interview questions',
    icon: '💼',
    systemPromptAddition:
        'You are also role-playing as a friendly interviewer. '
        'Ask common job interview questions one at a time. '
        'Give feedback on their answers and how they could improve. '
        'Start with "Tell me about yourself."',
  ),
  Scenario(
    id: 'travel',
    title: 'Travel Guide',
    description: 'Ask for directions, book hotels, explore a city',
    icon: '✈️',
    systemPromptAddition:
        'You are also role-playing as a local tour guide in New York City. '
        'Help the user navigate the city, recommend restaurants and sights. '
        'Start by asking where they\'d like to go today.',
  ),
  Scenario(
    id: 'restaurant',
    title: 'Restaurant',
    description: 'Order food and talk to the waiter',
    icon: '🍽️',
    systemPromptAddition:
        'You are also role-playing as a waiter at a nice restaurant. '
        'Present the specials, take orders, and make recommendations. '
        'Start by welcoming the user and offering a menu.',
  ),
  Scenario(
    id: 'doctor',
    title: 'Doctor\'s Office',
    description: 'Describe symptoms and understand medical advice',
    icon: '🏥',
    systemPromptAddition:
        'You are also role-playing as a friendly doctor. '
        'Ask about the user\'s symptoms, give advice, and explain things simply. '
        'Start by asking "What brings you in today?"',
  ),
];
