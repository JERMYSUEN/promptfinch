import { mkdtempSync, mkdirSync, rmSync, writeFileSync, chmodSync, existsSync, renameSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';

if (process.platform !== 'darwin') throw new Error('本機簽章身分只能在 macOS 建立。');
const bundleID = 'org.promptstudio.selection';
const support = resolve(homedir(), 'Library/Application Support/PromptSelection');
const configPath = process.env.PROMPT_STUDIO_SIGNING_CONFIG || resolve(support, 'code-signing.json');
if (existsSync(configPath)) throw new Error(`固定簽章設定已存在：${configPath}\n不會建立或覆蓋另一個簽章身分。`);

function run(command, args) {
  const result = spawnSync(command, args, { encoding: 'utf8', stdio: 'pipe' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} 未能完成：${(result.stderr || result.stdout || '').trim()}`);
  return result.stdout;
}

const keychainOutput = run('security', ['default-keychain', '-d', 'user']).trim();
const keychain = keychainOutput.replace(/^"|"$/g, '');
if (!keychain || !resolve(keychain).startsWith(resolve(homedir(), 'Library/Keychains') + '/')) {
  throw new Error('目前預設 Keychain 不是使用者 login Keychain，為避免寫入其他 Keychain 而停止。');
}

const temporary = mkdtempSync(join(tmpdir(), 'prompt-selection-signing-'));
chmodSync(temporary, 0o700);
const name = `PromptSelection Local Code Signing ${randomBytes(3).toString('hex')}`;
const keyPath = join(temporary, 'private-key.pem');
const certPath = join(temporary, 'certificate.pem');
const p12Path = join(temporary, 'identity.p12');
const configPathTemp = join(temporary, 'openssl.cnf');
const temporaryP12Password = randomBytes(24).toString('hex');
const certificateConfig = `[req]\ndistinguished_name=dn\nx509_extensions=code_signing\nprompt=no\n[dn]\nCN=${name}\n[code_signing]\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always\n`;

try {
  writeFileSync(configPathTemp, certificateConfig, { mode: 0o600 });
  run('openssl', ['req', '-new', '-x509', '-newkey', 'rsa:3072', '-nodes', '-sha256', '-days', '3650', '-config', configPathTemp, '-keyout', keyPath, '-out', certPath]);
  run('openssl', ['pkcs12', '-export', '-out', p12Path, '-inkey', keyPath, '-in', certPath, '-passout', `pass:${temporaryP12Password}`]);
  chmodSync(p12Path, 0o600);

  // -T restricts private-key use to Apple's code-signing tool. Never use -A.
  run('security', ['import', p12Path, '-k', keychain, '-f', 'pkcs12', '-x', '-T', '/usr/bin/codesign', '-P', temporaryP12Password]);
  const fingerprintLine = run('openssl', ['x509', '-in', certPath, '-noout', '-fingerprint', '-sha1']);
  const fingerprint = fingerprintLine.split('=').at(-1).replaceAll(':', '').trim().toUpperCase();
  if (!/^[A-F0-9]{40}$/.test(fingerprint)) throw new Error('無法讀取簽章憑證指紋。');

  let identities = run('security', ['find-identity', '-v', '-p', 'codesigning', keychain]);
  if (!identities.includes(fingerprint)) {
    // Trust only the dedicated certificate for code signing; do not alter SSL or system-wide trust.
    run('security', ['add-trusted-cert', '-r', 'trustRoot', '-p', 'codeSign', '-k', keychain, certPath]);
    identities = run('security', ['find-identity', '-v', '-p', 'codesigning', keychain]);
  }
  if (!identities.includes(fingerprint)) throw new Error('憑證已匯入，但 macOS 未列出有效的 Code Signing 身分。請檢查 login Keychain 的 codeSign 信任設定。');

  mkdirSync(support, { recursive: true, mode: 0o700 });
  const config = { version: 1, bundleID, certificateName: name, certificateSHA1: fingerprint };
  const tempConfig = `${configPath}.tmp-${process.pid}`;
  writeFileSync(tempConfig, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
  renameSync(tempConfig, configPath);
  console.log(`已建立固定本機簽章身分：${name}\n憑證指紋：${fingerprint}\n設定檔：${configPath}\n私鑰留在 login Keychain，存取限定 /usr/bin/codesign。`);
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
