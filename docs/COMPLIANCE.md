# VeritasPay Compliance & Regulatory Framework

**Legal, Compliance, and Regulatory Information**

Version 1.0 | Last Updated: November 2025

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Regulatory Framework](#regulatory-framework)
3. [KYC/AML Procedures](#kycaml-procedures)
4. [Transaction Monitoring](#transaction-monitoring)
5. [Data Privacy & Security](#data-privacy--security)
6. [Jurisdictional Compliance](#jurisdictional-compliance)
7. [Risk Assessment](#risk-assessment)
8. [Audit & Reporting](#audit--reporting)
9. [User Rights](#user-rights)
10. [Contact Information](#contact-information)

---

## Executive Summary

VeritasPay is committed to operating in full compliance with applicable laws and regulations in all jurisdictions where our services are offered. This document outlines our compliance framework, regulatory approach, and commitment to preventing financial crime.

### Core Principles

1. **Regulatory Compliance**: We comply with all applicable laws in our operating jurisdictions
2. **Anti-Money Laundering**: Robust AML procedures to prevent illicit finance
3. **Know Your Customer**: Comprehensive KYC to verify user identities
4. **Data Protection**: GDPR and privacy law compliance
5. **Transparency**: Clear communication of our compliance practices
6. **User Protection**: Safeguarding user interests and rights

---

## Regulatory Framework

### Applicable Regulations

#### United States

**Federal Level**:
- **Bank Secrecy Act (BSA)** - AML requirements
- **USA PATRIOT Act** - Enhanced due diligence
- **FinCEN Regulations** - Money Service Business (MSB) requirements
- **OFAC Sanctions** - Sanctions screening
- **SEC Regulations** - If applicable to token classification
- **State Money Transmitter Laws** - State-by-state licensing

**Our Approach**:
- Registered as Money Service Business (MSB) with FinCEN
- State money transmitter licenses in applicable states
- Comprehensive AML/KYC program
- Regular OFAC sanctions screening

#### European Union

**MiCA (Markets in Crypto-Assets Regulation)**:
- Authorization requirements for stablecoin issuers
- Reserve requirements and segregation
- Transparent reserve attestation
- Consumer protection measures
- Prudential safeguards

**AMLD5/AMLD6**:
- Anti-Money Laundering Directives
- Enhanced due diligence requirements
- Beneficial ownership transparency
- Transaction monitoring

**GDPR (General Data Protection Regulation)**:
- Data protection and privacy
- User consent requirements
- Right to data portability
- Right to be forgotten

**Our Approach**:
- Seeking MiCA authorization
- Full GDPR compliance
- EU representative appointed
- Regular reserve attestations

#### United Kingdom

**Financial Services and Markets Act 2000**:
- FCA registration and authorization
- Payment services regulations
- Electronic money regulations

**Money Laundering Regulations 2017**:
- Customer due diligence
- Transaction monitoring
- Suspicious activity reporting

**Our Approach**:
- FCA authorization application in progress
- Full MLR compliance
- UK Anti-Money Laundering Supervisor coordination

#### Other Key Jurisdictions

- **Canada**: FINTRAC registration (MSB)
- **Australia**: AUSTRAC registration
- **Singapore**: MAS licensing framework
- **Switzerland**: FINMA compliance
- **Japan**: FSA registration

---

## KYC/AML Procedures

### Know Your Customer (KYC)

#### Verification Levels

**Level 1 - Basic** (Limits: $1,000/transaction, $10,000/month):
```
Requirements:
- Email address verification
- Phone number verification
- Basic identity information
- Country of residence

Approval Time: Instant
Use Cases: Small transactions, testing
```

**Level 2 - Standard** (Limits: $10,000/transaction, $100,000/month):
```
Requirements:
- Level 1 requirements +
- Government-issued photo ID
- Proof of address (< 3 months old)
- Selfie verification
- Source of funds declaration

Approval Time: 1-2 business days
Use Cases: Regular users, merchants
```

**Level 3 - Enhanced** (Limits: $100,000/transaction, $1,000,000/month):
```
Requirements:
- Level 2 requirements +
- Bank statements (3 months)
- Tax identification number
- Video verification call
- Enhanced due diligence questionnaire
- Source of wealth documentation

Approval Time: 3-5 business days
Use Cases: High-volume users, institutions
```

**Level 4 - Institutional** (Custom limits):
```
Requirements:
- Corporate registration documents
- Board resolutions
- Beneficial ownership disclosure (UBO)
- Financial statements
- AML/CFT policies
- Compliance officer details

Approval Time: 1-2 weeks
Use Cases: Businesses, payment processors
```

#### Accepted Documents

**Identity Verification**:
- ✅ Passport (any country)
- ✅ National ID card
- ✅ Driver's license
- ✅ Residence permit
- ❌ Student ID, employee badges (not accepted)

**Proof of Address**:
- ✅ Utility bill (electric, water, gas)
- ✅ Bank statement
- ✅ Government-issued document
- ✅ Tax notice
- Must be < 3 months old

**Business Documents**:
- ✅ Certificate of incorporation
- ✅ Business registration
- ✅ Articles of association
- ✅ Tax registration certificate

### Anti-Money Laundering (AML)

#### AML Program Components

**1. Customer Identification Program (CIP)**:
- Identity verification before first transaction
- Risk-based enhanced due diligence
- Ongoing monitoring of customer activity
- Periodic re-verification

**2. Transaction Monitoring**:
```javascript
Monitored Parameters:
- Transaction size (> $10,000 flagged)
- Transaction frequency (velocity checks)
- Geographic patterns (high-risk countries)
- Network analysis (linked accounts)
- Behavioral anomalies
```

**3. Sanctions Screening**:
- OFAC (Office of Foreign Assets Control)
- UN Sanctions Lists
- EU Sanctions Lists
- UK HM Treasury
- INTERPOL notices
- PEP (Politically Exposed Persons) databases

**4. Suspicious Activity Reporting (SAR)**:
```
Triggers for SAR:
- Structuring (avoiding reporting thresholds)
- Unusual patterns inconsistent with profile
- Rapid movement of funds
- Multiple failed identity verification attempts
- Transactions to/from high-risk jurisdictions
- Customer refuses to provide information
```

**Filing Timeframe**:
- Suspicious activity: 30 days after detection
- Ongoing suspicious activity: 90-120 days

#### Risk-Based Approach

**Low Risk**:
- Verified users in low-risk jurisdictions
- Small transaction amounts
- Consistent patterns
- Enhanced Monitoring: Quarterly

**Medium Risk**:
- New users
- Moderate transaction volumes
- Limited verification
- Enhanced Monitoring: Monthly

**High Risk**:
- High transaction volumes
- High-risk jurisdictions
- PEPs (Politically Exposed Persons)
- Cash-intensive businesses
- Enhanced Monitoring: Real-time

**Prohibited**:
- Sanctioned individuals/entities
- Prohibited jurisdictions
- Shell banks
- Anonymous transactions (except small amounts)

---

## Transaction Monitoring

### Automated Monitoring System

#### Real-Time Checks

```javascript
For Every Transaction:
1. Sanctions screening (sender & recipient)
2. Country risk assessment
3. Transaction amount limits
4. Velocity checks (transactions per hour/day)
5. Wallet clustering (related addresses)
6. Smart contract interaction analysis
```

#### Risk Scoring Algorithm

```
Risk Score Calculation (0-100):

Base Score: 20 (all transactions)

Add points for:
+ 20: Unverified sender
+ 20: Unverified recipient
+ 15: Large transaction (> $10,000)
+ 15: High-risk country
+ 10: New recipient
+ 10: Unusual time (3-5 AM local time)
+ 10: Velocity exceeded

Subtract points for:
- 10: Both parties verified
- 10: Whitelisted recipient
- 5:  Regular pattern

Actions:
0-40: Auto-approve
41-70: Secondary review (automated)
71-85: Manual review (compliance officer)
86-100: Block + investigation
```

### Transaction Limits

| User Level | Per Transaction | Per Day | Per Month |
|------------|----------------|---------|-----------|
| Level 1 | $1,000 | $5,000 | $10,000 |
| Level 2 | $10,000 | $50,000 | $100,000 |
| Level 3 | $100,000 | $500,000 | $1,000,000 |
| Level 4 | Custom | Custom | Custom |

### Enhanced Due Diligence (EDD)

**Triggers**:
- Transactions > $50,000
- PEPs (Politically Exposed Persons)
- High-risk jurisdictions
- Unusual patterns
- Customer request for limit increase

**Additional Requirements**:
- Source of funds documentation
- Source of wealth declaration
- Video call verification
- Employer/business information
- Purpose of transaction
- Expected transaction patterns

---

## Data Privacy & Security

### GDPR Compliance

#### Data Protection Principles

1. **Lawfulness, Fairness, Transparency**
   - Clear privacy policy
   - User consent obtained
   - Transparent data usage

2. **Purpose Limitation**
   - Data collected only for specified purposes
   - KYC/AML compliance
   - Service provision
   - Fraud prevention

3. **Data Minimization**
   - Only necessary data collected
   - No excessive information requests

4. **Accuracy**
   - Data kept up-to-date
   - Users can update information
   - Periodic re-verification

5. **Storage Limitation**
   - Data retained only as long as necessary
   - Legal requirements: 5-7 years
   - Automated deletion after retention period

6. **Integrity & Confidentiality**
   - Encrypted storage (AES-256)
   - Encrypted transmission (TLS 1.3)
   - Access controls
   - Regular security audits

#### User Rights

**Right to Access**:
- Request copy of personal data
- Response time: 30 days
- Format: Machine-readable

**Right to Rectification**:
- Correct inaccurate data
- Update information
- Response time: 30 days

**Right to Erasure** ("Right to be Forgotten"):
- Delete personal data
- Exceptions:
  - Legal retention requirements (AML: 5-7 years)
  - Ongoing investigations
  - Legal obligations
- Partial deletion after retention period

**Right to Data Portability**:
- Export data in machine-readable format (JSON, CSV)
- Transfer to another service
- Free of charge

**Right to Object**:
- Object to data processing
- Opt-out of marketing
- Object to automated decision-making

### Data Security Measures

**Technical Safeguards**:
```
- Encryption at rest: AES-256
- Encryption in transit: TLS 1.3
- Database encryption: Field-level encryption for PII
- Key management: AWS KMS / HSM
- Access control: Role-based (RBAC)
- Authentication: Multi-factor (MFA)
- Logging: Comprehensive audit logs
- Monitoring: 24/7 SOC
- Backups: Daily encrypted backups
- Disaster recovery: RPO <1 hour, RTO <4 hours
```

**Organizational Safeguards**:
- Background checks for employees
- Security training (annual)
- Data access on need-to-know basis
- Confidentiality agreements
- Incident response plan
- Regular security audits

**Third-Party Compliance**:
- KYC providers: SOC 2 certified
- Cloud providers: ISO 27001, SOC 2
- Data processors: GDPR compliant
- Data processing agreements in place

---

## Jurisdictional Compliance

### Supported Jurisdictions

**Tier 1 - Full Service** (All features available):
- United States
- European Union (all member states)
- United Kingdom
- Canada
- Australia
- Switzerland
- Singapore
- Japan

**Tier 2 - Limited Service** (Some restrictions):
- Brazil
- India
- Mexico
- South Korea
- Taiwan
- UAE
- South Africa

**Prohibited Jurisdictions**:
- Countries under OFAC sanctions (Iran, North Korea, Syria, Cuba, etc.)
- High-risk jurisdictions per FATF
- Countries lacking AML framework

### Country-Specific Requirements

#### United States

**Federal**:
- FinCEN MSB registration ✅
- OFAC compliance program ✅
- SAR/CTR filing procedures ✅

**State Licenses** (in progress):
- New York (BitLicense)
- California
- Texas
- Florida
- (40+ other states)

#### European Union

**MiCA Requirements**:
- Capital requirements: €350,000 minimum
- Reserve segregation ✅
- Monthly reserve attestations ✅
- Recovery plan ✅
- Governance arrangements ✅

**Local Registration**:
- Ireland: Central Bank authorization (in progress)
- Germany: BaFin notification ✅
- France: AMF registration (in progress)

#### United Kingdom

**FCA Authorization**:
- E-Money Institution (EMI) application
- Crypto asset registration
- Payment services authorization
- Ongoing compliance obligations

---

## Risk Assessment

### Enterprise Risk Management

#### Risk Categories

**1. Regulatory Risk**
- **Description**: Changes in regulations affecting operations
- **Mitigation**:
  - Proactive engagement with regulators
  - Compliance team monitoring regulatory developments
  - Flexible business model
  - Jurisdictional diversification

**2. Financial Crime Risk**
- **Description**: Use of platform for money laundering, terrorism financing
- **Mitigation**:
  - Robust KYC/AML procedures
  - Transaction monitoring
  - Sanctions screening
  - SAR filing procedures
  - Law enforcement cooperation

**3. Operational Risk**
- **Description**: System failures, fraud, errors
- **Mitigation**:
  - Redundant systems
  - Business continuity plan
  - Disaster recovery
  - Insurance coverage
  - Regular testing

**4. Technology Risk**
- **Description**: Smart contract vulnerabilities, hacks
- **Mitigation**:
  - Multiple security audits
  - Bug bounty program
  - Insurance fund
  - Emergency pause mechanisms
  - Multi-signature controls

**5. Market Risk**
- **Description**: Collateral volatility, liquidity issues
- **Mitigation**:
  - Over-collateralization (150%+)
  - Diversified collateral
  - Liquidation mechanisms
  - Circuit breakers
  - Insurance pool

### Ongoing Risk Assessment

**Frequency**: Quarterly comprehensive review

**Process**:
1. Identify emerging risks
2. Assess likelihood and impact
3. Implement mitigation measures
4. Monitor effectiveness
5. Report to board/regulators

---

## Audit & Reporting

### Internal Audits

**Frequency**: Quarterly

**Scope**:
- KYC/AML procedures
- Transaction monitoring effectiveness
- Data security controls
- Regulatory compliance
- Operational procedures

**Auditor**: External independent auditor

### External Audits

**Financial Audit**: Annual
- Auditor: Big 4 accounting firm
- Standards: GAAP/IFRS
- Public disclosure of results

**Reserve Attestation**: Monthly
- Third-party verification
- Proof of reserves
- Collateral composition
- Public disclosure

**Smart Contract Audit**: Ongoing
- Trail of Bits
- OpenZeppelin
- ChainSecurity
- Public disclosure of findings

### Regulatory Reporting

**FinCEN (USA)**:
- Currency Transaction Reports (CTR): > $10,000
- Suspicious Activity Reports (SAR): As needed
- Registration renewal: Bi-annually

**FCA (UK)**:
- Annual report
- Quarterly returns
- Ad-hoc reporting

**EU Regulators**:
- Monthly reserve attestations
- Quarterly prudential reports
- Annual audited financials

### Public Transparency

**Published Quarterly**:
- Reserve composition
- Total VPUSD in circulation
- Collateral ratio
- Transaction volume (aggregated)
- Security audit updates

**Real-Time Dashboard**:
- Live reserve ratio
- Total supply
- Blockchain transactions (public)

---

## User Rights

### Complaint Procedure

**Step 1 - Contact Support**:
- Email: compliance@veritaspay.io
- Response time: 48 hours
- Reference number provided

**Step 2 - Escalation**:
- If unsatisfied, request escalation
- Review by Compliance Officer
- Response time: 5 business days

**Step 3 - External Resolution**:
- Financial Ombudsman (UK)
- Consumer Financial Protection Bureau (US)
- Local regulators in your jurisdiction

### Account Restrictions

**Reasons for Restriction**:
- Failed KYC verification
- Suspicious activity
- Regulatory requirement
- Sanctions screening hit

**User Rights**:
- Notification of restriction
- Reason for restriction (if permissible)
- Ability to appeal
- Access to funds after investigation

**Appeal Process**:
1. Submit appeal with supporting documents
2. Review within 10 business days
3. Decision communicated
4. Further appeal to regulator if unsatisfied

### Fund Protection

**Segregation**:
- User funds segregated from company funds
- Held in trust accounts
- Not used for operational expenses

**Insurance**:
- Smart contract insurance ($50M coverage)
- Cyber insurance ($10M coverage)
- Directors & Officers insurance

**Bankruptcy Protection**:
- User funds not subject to company creditors
- Segregated accounts protected
- Priority claim in unlikely insolvency

---

## Contact Information

### Compliance Department

**Email**: compliance@veritaspay.io
**Phone**: +1 (555) COMPLY-1
**Hours**: Monday-Friday, 9 AM - 6 PM EST

### Mailing Address

```
VeritasPay Compliance Department
123 Blockchain Avenue, Suite 500
Financial District
New York, NY 10004
United States
```

### Regulatory Inquiries

**Regulators**: regulatory@veritaspay.io
**Law Enforcement**: legal@veritaspay.io
**Media**: press@veritaspay.io

### Report Suspicious Activity

**Confidential Hotline**: +1 (555) REPORT-1
**Email**: sar@veritaspay.io
**Anonymous Web Form**: https://veritaspay.io/report

---

## Legal Disclaimers

### Terms of Service

Full Terms of Service available at: https://veritaspay.io/terms

**Key Points**:
- By using VeritasPay, you agree to our Terms
- We reserve right to refuse service
- We may update terms with notice
- Disputes governed by arbitration

### Privacy Policy

Full Privacy Policy available at: https://veritaspay.io/privacy

**Key Points**:
- We collect only necessary information
- Your data is encrypted and secured
- We comply with GDPR and applicable laws
- You have rights to access, rectify, delete your data

### Risk Disclosure

**Important Risks**:
- Cryptocurrency markets are volatile
- Stablecoins may lose peg in extreme circumstances
- Smart contracts may have vulnerabilities
- Regulatory changes may affect availability
- Irreversible transactions - no chargebacks

**Our Mitigation**:
- Over-collateralization (150%+)
- Multiple security audits
- Insurance fund
- Circuit breakers
- Compliance with regulations

### Prohibited Use

**We Do Not Permit**:
- Money laundering
- Terrorism financing
- Sanctions evasion
- Illegal activities
- Prohibited jurisdictions
- Age < 18 years

**Consequences**:
- Account termination
- Fund seizure (if legal requirement)
- Law enforcement notification
- Legal action

---

## Updates & Amendments

**Version History**:
- v1.0 (November 2025): Initial release

**Amendment Policy**:
- Material changes: 30 days notice
- Non-material changes: Immediate effect
- Notification via email + website

**How to Stay Informed**:
- Subscribe to compliance updates: https://veritaspay.io/compliance-updates
- Follow @VeritasPayCompliance on Twitter
- Check our blog: https://blog.veritaspay.io

---

## Conclusion

VeritasPay is committed to the highest standards of regulatory compliance, user protection, and transparency. We work closely with regulators worldwide to ensure our services are safe, legal, and beneficial to our users.

If you have any questions about our compliance practices, please don't hesitate to contact us at compliance@veritaspay.io.

---

**Last Updated**: November 2025
**Next Review**: February 2026

**Document Version**: 1.0
**Approved By**: Chief Compliance Officer

---

*This document is for informational purposes and does not constitute legal advice. For specific legal questions, please consult a qualified attorney in your jurisdiction.*
