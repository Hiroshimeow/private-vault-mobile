package io.hiroshimeow.private_vault_mobile;

import android.os.Binder;
import android.os.IBinder;
import android.os.Parcel;
import android.os.RemoteException;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.TimeUnit;

public final class CloneProfileUserService extends Binder {
    public static final String DESCRIPTOR =
            "io.hiroshimeow.private_vault_mobile.CloneProfileUserService";
    public static final int TRANSACTION_EXEC = IBinder.FIRST_CALL_TRANSACTION;

    public CloneProfileUserService() {
        attachInterface(null, DESCRIPTOR);
    }

    @Override
    protected boolean onTransact(
            int code,
            Parcel data,
            Parcel reply,
            int flags
    ) throws RemoteException {
        if (code != TRANSACTION_EXEC) {
            return super.onTransact(code, data, reply, flags);
        }
        data.enforceInterface(DESCRIPTOR);
        final String operation = data.readString();
        final ArrayList<String> arguments = data.createStringArrayList();
        final CommandResult result = execute(
                operation,
                arguments == null ? List.of() : arguments
        );
        reply.writeNoException();
        reply.writeInt(result.exitCode);
        reply.writeString(result.stdout);
        reply.writeString(result.stderr);
        return true;
    }

    private CommandResult execute(String operation, List<String> arguments) {
        try {
            final String[] command = commandFor(operation, arguments);
            final Process process = new ProcessBuilder(command)
                    .redirectErrorStream(false)
                    .start();
            final boolean finished = process.waitFor(20, TimeUnit.SECONDS);
            if (!finished) {
                process.destroyForcibly();
                return new CommandResult(124, "", "operation timed out");
            }
            final String stdout = readBounded(process.getInputStream());
            final String stderr = readBounded(process.getErrorStream());
            return new CommandResult(process.exitValue(), stdout, stderr);
        } catch (Exception error) {
            return new CommandResult(125, "", String.valueOf(error.getMessage()));
        }
    }

    private String[] commandFor(String operation, List<String> args) {
        if ("list-users".equals(operation) && args.isEmpty()) {
            return new String[]{"cmd", "user", "list", "-v"};
        }
        if ("current-user".equals(operation) && args.isEmpty()) {
            return new String[]{"am", "get-current-user"};
        }
        if ("create-clone".equals(operation) && args.size() == 1) {
            final String parent = requireNumeric(args.get(0));
            return new String[]{
                    "pm", "create-user",
                    "--profileOf", parent,
                    "--user-type", "android.os.usertype.profile.CLONE",
                    "PrivateVaultClone"
            };
        }
        if ("start-user".equals(operation) && args.size() == 1) {
            return new String[]{"am", "start-user", "-w", requireNumeric(args.get(0))};
        }
        if ("list-packages".equals(operation) && args.size() == 1) {
            return new String[]{
                    "cmd", "package", "list", "packages",
                    "--user", requireNumeric(args.get(0))
            };
        }
        if ("install-existing".equals(operation) && args.size() == 2) {
            return new String[]{
                    "cmd", "package", "install-existing",
                    "--user", requireNumeric(args.get(0)),
                    requirePackage(args.get(1))
            };
        }
        if ("uninstall".equals(operation) && args.size() == 2) {
            return new String[]{
                    "cmd", "package", "uninstall",
                    "--user", requireNumeric(args.get(0)),
                    requirePackage(args.get(1))
            };
        }
        if ("resolve-activity".equals(operation) && args.size() == 2) {
            return new String[]{
                    "cmd", "package", "resolve-activity",
                    "--brief", "--user", requireNumeric(args.get(0)),
                    requirePackage(args.get(1))
            };
        }
        if ("launch".equals(operation) && args.size() == 2) {
            return new String[]{
                    "am", "start",
                    "--user", requireNumeric(args.get(0)),
                    "-n", requireComponent(args.get(1))
            };
        }
        throw new IllegalArgumentException("unsupported clone operation");
    }

    private String requireNumeric(String value) {
        if (!value.matches("[0-9]{1,6}")) {
            throw new IllegalArgumentException("invalid user id");
        }
        return value;
    }

    private String requirePackage(String value) {
        if (!value.matches("[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+")) {
            throw new IllegalArgumentException("invalid package name");
        }
        return value;
    }

    private String requireComponent(String value) {
        if (!value.matches("[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+/[A-Za-z0-9_.$]+")) {
            throw new IllegalArgumentException("invalid component");
        }
        return value;
    }

    private String readBounded(InputStream stream) throws Exception {
        final ByteArrayOutputStream output = new ByteArrayOutputStream();
        final byte[] buffer = new byte[4096];
        int remaining = 256 * 1024;
        while (remaining > 0) {
            final int count = stream.read(buffer, 0, Math.min(buffer.length, remaining));
            if (count < 0) break;
            output.write(buffer, 0, count);
            remaining -= count;
        }
        return output.toString(StandardCharsets.UTF_8);
    }

    private record CommandResult(int exitCode, String stdout, String stderr) {}
}
