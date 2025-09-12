#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const auditResults = {
  timestamp: new Date().toISOString(),
  serviceRoleUsage: [],
  forbiddenReferences: [],
  ambiguousContractId: [],
  duplicateRPCs: []
};

// Scan for SERVICE_ROLE usage in client code
function scanServiceRoleUsage() {
  const clientDirs = ['src/components', 'src/hooks', 'src/lib'];
  
  clientDirs.forEach(dir => {
    const fullPath = path.join(process.cwd(), dir);
    if (fs.existsSync(fullPath)) {
      scanDirectory(fullPath, (filePath, content) => {
        if (content.includes('SERVICE_ROLE') || content.includes('service_role_key')) {
          auditResults.serviceRoleUsage.push({
            file: path.relative(process.cwd(), filePath),
            severity: 'HIGH',
            issue: 'SERVICE_ROLE key usage in client code'
          });
        }
      });
    }
  });
}

// Scan for forbidden references
function scanForbiddenReferences() {
  const srcPath = path.join(process.cwd(), 'src');
  scanDirectory(srcPath, (filePath, content) => {
    if (content.includes('students.teacher_id')) {
      auditResults.forbiddenReferences.push({
        file: path.relative(process.cwd(), filePath),
        line: findLineNumber(content, 'students.teacher_id'),
        issue: 'students.teacher_id reference'
      });
    }
  });
}

// Scan for ambiguous contract_id
function scanAmbiguousContractId() {
  const srcPath = path.join(process.cwd(), 'src');
  scanDirectory(srcPath, (filePath, content) => {
    const lines = content.split('\n');
    lines.forEach((line, index) => {
      if (line.includes('contract_id') && !line.includes('contracts.contract_id') && !line.includes('c.contract_id')) {
        auditResults.ambiguousContractId.push({
          file: path.relative(process.cwd(), filePath),
          line: index + 1,
          content: line.trim(),
          issue: 'Unqualified contract_id reference'
        });
      }
    });
  });
}

// Scan for duplicate RPC names
function scanDuplicateRPCs() {
  const migrationsPath = path.join(process.cwd(), 'supabase/migrations');
  const rpcMap = new Map();
  
  if (fs.existsSync(migrationsPath)) {
    fs.readdirSync(migrationsPath).forEach(file => {
      if (file.endsWith('.sql')) {
        const content = fs.readFileSync(path.join(migrationsPath, file), 'utf8');
        const rpcMatches = content.match(/CREATE\s+(OR\s+REPLACE\s+)?FUNCTION\s+(\w+)/gi);
        
        if (rpcMatches) {
          rpcMatches.forEach(match => {
            const functionName = match.match(/FUNCTION\s+(\w+)/i)[1];
            if (!rpcMap.has(functionName)) {
              rpcMap.set(functionName, []);
            }
            rpcMap.get(functionName).push(file);
          });
        }
      }
    });
  }
  
  rpcMap.forEach((files, functionName) => {
    if (files.length > 1) {
      auditResults.duplicateRPCs.push({
        function: functionName,
        files: files,
        issue: 'Function defined in multiple migration files'
      });
    }
  });
}

// Helper functions
function scanDirectory(dir, callback) {
  const items = fs.readdirSync(dir);
  
  items.forEach(item => {
    const fullPath = path.join(dir, item);
    const stat = fs.statSync(fullPath);
    
    if (stat.isDirectory()) {
      scanDirectory(fullPath, callback);
    } else if (stat.isFile() && (item.endsWith('.ts') || item.endsWith('.tsx') || item.endsWith('.js'))) {
      const content = fs.readFileSync(fullPath, 'utf8');
      callback(fullPath, content);
    }
  });
}

function findLineNumber(content, searchTerm) {
  const lines = content.split('\n');
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].includes(searchTerm)) {
      return i + 1;
    }
  }
  return -1;
}

// Run audit
console.log('Running MAM WebApp code audit...');

scanServiceRoleUsage();
scanForbiddenReferences();
scanAmbiguousContractId();
scanDuplicateRPCs();

// Ensure directories exist
const docsAuditDir = path.join(process.cwd(), 'docs', 'audit');
if (!fs.existsSync(docsAuditDir)) {
  fs.mkdirSync(docsAuditDir, { recursive: true });
}

// Write JSON report
const jsonReportPath = path.join(docsAuditDir, 'CODE_AUDIT_REPORT.json');
fs.writeFileSync(jsonReportPath, JSON.stringify(auditResults, null, 2));

// Write summary
const summaryPath = path.join(docsAuditDir, 'CODE_AUDIT_SUMMARY.md');
const summary = generateSummary(auditResults);
fs.writeFileSync(summaryPath, summary);

console.log(`Audit complete. Reports written to:`);
console.log(`- ${jsonReportPath}`);
console.log(`- ${summaryPath}`);

function generateSummary(results) {
  let summary = `# Code Audit Summary\n\n`;
  summary += `**Timestamp:** ${results.timestamp}\n\n`;
  
  summary += `## Issues Found\n\n`;
  
  if (results.serviceRoleUsage.length > 0) {
    summary += `### HIGH SEVERITY: SERVICE_ROLE Usage (${results.serviceRoleUsage.length})\n`;
    results.serviceRoleUsage.forEach(issue => {
      summary += `- \`${issue.file}\`: ${issue.issue}\n`;
    });
    summary += `\n`;
  }
  
  if (results.forbiddenReferences.length > 0) {
    summary += `### Forbidden References (${results.forbiddenReferences.length})\n`;
    results.forbiddenReferences.forEach(issue => {
      summary += `- \`${issue.file}:${issue.line}\`: ${issue.issue}\n`;
    });
    summary += `\n`;
  }
  
  if (results.ambiguousContractId.length > 0) {
    summary += `### Ambiguous contract_id References (${results.ambiguousContractId.length})\n`;
    results.ambiguousContractId.forEach(issue => {
      summary += `- \`${issue.file}:${issue.line}\`: ${issue.content}\n`;
    });
    summary += `\n`;
  }
  
  if (results.duplicateRPCs.length > 0) {
    summary += `### Duplicate RPC Functions (${results.duplicateRPCs.length})\n`;
    results.duplicateRPCs.forEach(issue => {
      summary += `- \`${issue.function}\`: Found in ${issue.files.join(', ')}\n`;
    });
    summary += `\n`;
  }
  
  if (results.serviceRoleUsage.length === 0 && results.forbiddenReferences.length === 0 && 
      results.ambiguousContractId.length === 0 && results.duplicateRPCs.length === 0) {
    summary += `✅ No issues found.\n`;
  }
  
  return summary;
}
