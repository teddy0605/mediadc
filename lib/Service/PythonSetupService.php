<?php

declare(strict_types=1);

namespace OCA\MediaDC\Service;

use OCA\MediaDC\AppInfo\Application;
use Psr\Log\LoggerInterface;

class PythonSetupService {
	public function __construct(
		private readonly LoggerInterface $logger,
		private readonly CPAUtilsService $cpaUtils,
	) {
	}

	/**
	 * Check if the Python venv is ready to run MediaDC tasks.
	 */
	public function isReady(): bool {
		$appPath = \OC::$SERVERROOT . '/apps/' . Application::APP_ID;
		$pythonBin = $appPath . '/.venv/bin/python3';
		return file_exists($pythonBin) && is_executable($pythonBin);
	}

	/**
	 * Set up the Python virtual environment and install required packages.
	 * Called during app enable (repair step) and as a pre-flight check before
	 * running the Python worker.
	 *
	 * @return array{success: bool, message: string, ready: bool}
	 */
	public function setup(): array {
		if ($this->isReady()) {
			return ['success' => true, 'message' => 'Python environment already set up', 'ready' => true];
		}

		if (!$this->cpaUtils->isFunctionEnabled('exec')) {
			$msg = 'PHP exec() is disabled — cannot set up Python environment';
			$this->logger->error($msg);
			return ['success' => false, 'message' => $msg, 'ready' => false];
		}

		$appPath = \OC::$SERVERROOT . '/apps/' . Application::APP_ID;

		// Check python3 is available
		exec('which python3 2>/dev/null', $output, $rc);
		if ($rc !== 0) {
			$msg = 'python3 not found on system — please install Python 3';
			$this->logger->error($msg);
			return ['success' => false, 'message' => $msg, 'ready' => false];
		}

		// Try to create venv
		exec('python3 -m venv ' . escapeshellarg($appPath . '/.venv') . ' 2>&1', $output, $rc);
		if ($rc !== 0) {
			$stderr = implode("\n", $output);
			$this->logger->warning('venv creation failed, trying apt install python3-venv: {error}', ['error' => $stderr]);

			// Try to install python3-venv on Debian/Ubuntu
			exec('apt-get update -qq 2>&1 && apt-get install -y -qq python3-venv 2>&1', $aptOutput, $aptRc);
			if ($aptRc === 0) {
				exec('python3 -m venv ' . escapeshellarg($appPath . '/.venv') . ' 2>&1', $output, $rc);
			}

			if ($rc !== 0) {
				$msg = 'Failed to create Python venv: ' . implode("\n", $output);
				$this->logger->error($msg);
				return ['success' => false, 'message' => $msg, 'ready' => false];
			}
		}

		// Install packages
		$pipBin = $appPath . '/.venv/bin/pip';
		$requirementsPath = $appPath . '/requirements.txt';

		if (!file_exists($requirementsPath)) {
			$msg = 'requirements.txt not found';
			$this->logger->error($msg);
			return ['success' => false, 'message' => $msg, 'ready' => false];
		}

		exec(
			escapeshellarg($pipBin) . ' install --quiet -r ' . escapeshellarg($requirementsPath) . ' 2>&1',
			$pipOutput,
			$pipRc
		);

		if ($pipRc !== 0) {
			$msg = 'Failed to install Python packages: ' . implode("\n", $pipOutput);
			$this->logger->error($msg);
			return ['success' => false, 'message' => $msg, 'ready' => false];
		}

		$this->logger->info('Python environment set up successfully');
		return ['success' => true, 'message' => 'Python environment set up successfully', 'ready' => true];
	}
}
