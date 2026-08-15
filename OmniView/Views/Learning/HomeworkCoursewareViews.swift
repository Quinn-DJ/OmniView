import SwiftUI

// MARK: - 作业待办

struct HomeworkView: View {
    @EnvironmentObject private var viewModel: ZJUViewModel
    @State private var showFinished = false

    var body: some View {
        Group {
            if !viewModel.isLoggedIn {
                ZJULoginView(title: "作业待办", subtitle: "登录学在浙大后查看作业、测验与截止时间")
            } else {
                content
            }
        }
        .navigationTitle("作业待办")
    }

    private var content: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let error = viewModel.errorMessage, viewModel.homeworks.isEmpty {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") {
                        Task { await viewModel.refreshHomework() }
                    }
                }
            } else if viewModel.isLoadingHomework && viewModel.homeworks.isEmpty {
                ProgressView("正在加载作业…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.homeworks.isEmpty {
                ContentUnavailableView {
                    Label("暂无作业", systemImage: "checkmark.circle")
                } description: {
                    Text("太棒了，当前没有未完成的作业")
                }
            } else {
                homeworkList
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Toggle("显示已提交", isOn: $showFinished)
                .toggleStyle(.checkbox)
            Spacer()
            if let updated = viewModel.lastUpdated {
                Text("更新于 \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await viewModel.refreshHomework() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isLoadingHomework)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var homeworkList: some View {
        let filtered = viewModel.homeworks.filter { showFinished || !$0.submitted }
        let overdue = filtered.filter { $0.ddl < Date() && !$0.submitted }
        let upcoming = filtered.filter { $0.ddl >= Date() || $0.submitted }

        return List {
            if !overdue.isEmpty {
                Section("已逾期 · \(overdue.count)") {
                    ForEach(overdue) { homework in
                        HomeworkRow(homework: homework)
                    }
                }
            }
            if !upcoming.isEmpty {
                Section("进行中 · \(upcoming.count)") {
                    ForEach(upcoming) { homework in
                        HomeworkRow(homework: homework)
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}

struct HomeworkRow: View {
    let homework: ZJUHomework

    private static let ddlFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: homework.submitted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(homework.submitted ? Color.green : Color.orange)
                Text(homework.title)
                    .font(.body.weight(.medium))
                    .strikethrough(homework.submitted)
                Spacer()
                if homework.submitted {
                    Text("已提交")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                }
            }
            HStack(spacing: 12) {
                Label(homework.course, systemImage: "book.closed")
                Label(Self.ddlFormatter.string(from: homework.ddl), systemImage: "clock")
                    .foregroundStyle(ddlColor)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !homework.description.isEmpty {
                Text(homework.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !homework.uploads.isEmpty {
                HStack(spacing: 6) {
                    ForEach(homework.uploads) { upload in
                        Label(upload.name, systemImage: "paperclip")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var ddlColor: Color {
        guard !homework.submitted else { return .secondary }
        let hours = homework.ddl.timeIntervalSinceNow / 3600
        if hours < 24 { return .red }
        if hours < 72 { return .orange }
        return .secondary
    }
}

// MARK: - 课件

struct CoursewareView: View {
    @EnvironmentObject private var viewModel: ZJUViewModel

    var body: some View {
        Group {
            if !viewModel.isLoggedIn {
                ZJULoginView(title: "课件", subtitle: "登录学在浙大后查看并下载课程课件")
            } else {
                content
            }
        }
        .navigationTitle("课件")
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if let updated = viewModel.lastUpdated {
                    Text("更新于 \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await viewModel.refreshMaterials() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoadingMaterials)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if let error = viewModel.errorMessage, viewModel.courseMaterials.isEmpty {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") {
                        Task { await viewModel.refreshMaterials() }
                    }
                }
            } else if viewModel.isLoadingMaterials && viewModel.courseMaterials.isEmpty {
                ProgressView("正在加载课件…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.courseMaterials.isEmpty {
                ContentUnavailableView {
                    Label("暂无课件", systemImage: "doc.richtext")
                } description: {
                    Text("当前学期没有可用的课件资料")
                }
            } else {
                materialList
            }
        }
    }

    private var materialList: some View {
        List {
            ForEach(viewModel.courseMaterials) { entry in
                if !entry.materials.isEmpty {
                    Section(entry.course.name) {
                        ForEach(entry.materials) { material in
                            MaterialRow(material: material, courseName: entry.course.name)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}

struct MaterialRow: View {
    @EnvironmentObject private var viewModel: ZJUViewModel
    let material: ZJUMaterial
    let courseName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(material.title, systemImage: "doc.text")
                .font(.body.weight(.medium))
            ForEach(material.uploads) { upload in
                UploadRow(upload: upload, courseName: courseName)
            }
        }
        .padding(.vertical, 2)
    }
}

struct UploadRow: View {
    @EnvironmentObject private var viewModel: ZJUViewModel
    let upload: ZJUUpload
    let courseName: String

    @State private var isDownloading = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
            Text(upload.name)
                .font(.caption)
                .lineLimit(1)
            Spacer()

            if let error = viewModel.downloadErrors[upload.id] {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            } else if let progress = viewModel.downloadProgress[upload.id], progress > 0, progress < 1 {
                ProgressView(value: progress)
                    .frame(width: 80)
            } else if viewModel.downloadProgress[upload.id] == 1.0 {
                Text("已下载")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }

            Button {
                download()
            } label: {
                Image(systemName: "arrow.down.circle")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.downloadProgress[upload.id] != nil
                && viewModel.downloadProgress[upload.id]! > 0
                && viewModel.downloadProgress[upload.id]! < 1)
        }
        .padding(.leading, 16)
    }

    private var iconName: String {
        let name = upload.name.lowercased()
        if name.hasSuffix(".pdf") { return "doc.richtext" }
        if name.hasSuffix(".pptx") || name.hasSuffix(".ppt") { return "chart.bar.doc.horizontal" }
        if name.hasSuffix(".docx") || name.hasSuffix(".doc") { return "doc.plaintext" }
        if name.hasSuffix(".xlsx") || name.hasSuffix(".xls") { return "tablecells" }
        if name.hasSuffix(".zip") || name.hasSuffix(".rar") { return "archivebox" }
        return "paperclip"
    }

    private func download() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = upload.name
        panel.title = "保存课件"
        panel.prompt = "下载"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                await viewModel.download(upload: upload, to: url)
            }
        }
    }
}

// MARK: - 未登录提示（引导前往「设置」）

struct ZJULoginView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button {
                openSettings()
            } label: {
                Label("打开设置…", systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
