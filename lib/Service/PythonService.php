<?php

declare(strict_types=1);

namespace OCA\MediaDC\Service;

use Psr\Log\LoggerInterface;

class PythonService {
	public function __construct(
		private readonly LoggerInterface $logger,
		private readonly CPAUtilsService $cpaUtils,
		private readonly PythonSetupService $pythonSetup,
	) {
	}

	/**
	 * Run a Python script in the app directory.
	 *
	 * @param string $appId app id (e.g. 'mediadc')
	 * @param string $scriptName script path relative to the app directory (e.g. 'main.py')
	 * @param array $scriptParams CLI arguments as key=>value pairs
	 * @param bool $nonBlocking run asynchronously with nohup
	 * @param array $env environment variables as key=>value pairs
	 * @param bool $binary unused — kept for API compatibility (always source mode)
	 *
	 * @return array|void
	 */
	public function run(
		string $appId,
		string $scriptName,
		array $scriptParams = [],
		bool $nonBlocking = false,
		array $env = [],
		bool $binary = false,
	) {
		if (!$this->cpaUtils->isFunctionEnabled('exec')) {
			$this->logger->error('PHP exec() is not available');
			return;
		}

		// Auto-setup Python environment if not ready
		if (!$this->pythonSetup->isReady()) {
			$setupResult = $this->pythonSetup->setup();
			if (!$setupResult['ready']) {
				$msg = 'Python environment not ready: ' . $setupResult['message'];
				$this->logger->error($msg);
				return ['output' => [], 'result_code' => -1, 'errors' => $msg];
			}
		}

		$appPath = \OC::$SERVERROOT . '/apps/' . $appId;
		$pythonBin = $appPath . '/.venv/bin/python3';
		$cmd = escapeshellarg($pythonBin) . ' ' . escapeshellarg($appPath . '/' . $scriptName);

		foreach ($scriptParams as $key => $value) {
			if ($value === '') {
				$cmd .= ' ' . escapeshellarg($key);
			} else {
				$cmd .= ' ' . escapeshellarg($key) . ' ' . escapeshellarg((string)$value);
			}
		}

		$envStr = '';
		foreach ($env as $key => $value) {
			$strValue = (string)$value;
			// Skip empty env vars — they break shell parsing:
			// "VAR= OTHER=val cmd" makes bash run "OTHER=val" as the command
			if ($strValue === '') {
				continue;
			}
			$envStr .= $key . '=' . escapeshellarg($strValue) . ' ';
		}

		// Use 'env' to set env vars — avoids shell word-splitting issues
		$prefixedCmd = 'env ' . $envStr . $cmd;
		$prefixedNohupCmd = 'env ' . $envStr . 'nohup ' . $cmd;

		if ($nonBlocking) {
			$logDir = \OC::$SERVERROOT . '/data/appdata_' . \OC::$server->getConfig()->getSystemValue('instanceid')
				. '/' . $appId . '/logs';
			@mkdir($logDir, 0755, true);
			$logFile = $logDir . '/task_' . date('Y-m-d_H-i-s') . '.log';
			exec($prefixedNohupCmd . ' > ' . escapeshellarg($logFile) . ' 2>&1 &');
			// Brief wait then check if nohup actually launched successfully
			usleep(500000); // 0.5s
			if (file_exists($logFile)) {
				$earlyOutput = @file_get_contents($logFile);
				if ($earlyOutput !== false && str_starts_with($earlyOutput, 'nohup: failed to run command')) {
					$this->logger->error('Python worker failed to start: {error}', ['error' => $earlyOutput]);
				}
			}
			return;
		}

		exec($prefixedCmd, $output, $resultCode);
		$errors = '';

		if ($resultCode !== 0) {
			$firstLine = $output[0] ?? '';
			$decoded = json_decode($firstLine, true);
			if ($decoded !== null) {
				$errors = $firstLine;
			} else {
				exec($prefixedCmd . ' 2>&1', $stderrOutput);
				$errors = implode("\n", $stderrOutput);
			}
		}

		return [
			'output' => $output,
			'result_code' => $resultCode,
			'errors' => $errors,
		];
	}
}
