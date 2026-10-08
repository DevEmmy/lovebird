/// Countries offered at sign-up → their default currency.
/// Currency drives localized prices (e.g. Couple of the Year fee) — never hard-coded globally.
const countries = <(String code, String name, String currency)>[
  ('NG', 'Nigeria', 'NGN'),
  ('GH', 'Ghana', 'GHS'),
  ('KE', 'Kenya', 'KES'),
  ('ZA', 'South Africa', 'ZAR'),
  ('EG', 'Egypt', 'EGP'),
  ('US', 'United States', 'USD'),
  ('CA', 'Canada', 'CAD'),
  ('GB', 'United Kingdom', 'GBP'),
  ('IE', 'Ireland', 'EUR'),
  ('DE', 'Germany', 'EUR'),
  ('NL', 'Netherlands', 'EUR'),
  ('FR', 'France', 'EUR'),
  ('ES', 'Spain', 'EUR'),
  ('IT', 'Italy', 'EUR'),
  ('BE', 'Belgium', 'EUR'),
  ('SE', 'Sweden', 'SEK'),
  ('NO', 'Norway', 'NOK'),
  ('PL', 'Poland', 'PLN'),
  ('AE', 'United Arab Emirates', 'AED'),
  ('SA', 'Saudi Arabia', 'SAR'),
  ('IN', 'India', 'INR'),
  ('PK', 'Pakistan', 'PKR'),
  ('PH', 'Philippines', 'PHP'),
  ('SG', 'Singapore', 'SGD'),
  ('JP', 'Japan', 'JPY'),
  ('KR', 'South Korea', 'KRW'),
  ('AU', 'Australia', 'AUD'),
  ('NZ', 'New Zealand', 'NZD'),
  ('BR', 'Brazil', 'BRL'),
  ('MX', 'Mexico', 'MXN'),
];

const currencies = ['NGN', 'GHS', 'KES', 'ZAR', 'EGP', 'USD', 'CAD', 'GBP', 'EUR', 'SEK', 'NOK', 'PLN', 'AED', 'SAR', 'INR', 'PKR', 'PHP', 'SGD', 'JPY', 'KRW', 'AUD', 'NZD', 'BRL', 'MXN'];

String currencyForCountry(String? code) =>
    countries.firstWhere((c) => c.$1 == code, orElse: () => ('', '', 'USD')).$3;

String countryName(String? code) =>
    countries.firstWhere((c) => c.$1 == code, orElse: () => (code ?? '', code ?? 'Unknown', '')).$2;
