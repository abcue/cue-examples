package cluster

import (
	"encoding/json"
	"regexp"
	"strings"
	"tool/cli"
	"tool/exec"
	"tool/file"
)

command: {
	_pkgId: {for p in [for v, vv in cluster.apiResources for k, kv in vv {kv.package}] {
		(p): strings.Replace(regexp.ReplaceAll("[/.]", strings.TrimPrefix(p, "k8s.io/api/"), ""), "apiserver", "", -1)
	}}
	let FN = "cluster.cue"
	generate: {
		imports: cli.Print & {
			_exclude: {
				apiextensionsv1:   _
				apiregistrationv1: _
			}
			text: strings.Join([for p, i in _pkgId if _exclude[i] == _|_ let P = regexp.ReplaceAll("\\.[^/]*(/[^/]+)$", p, "$1") {
				#"\#(i) "\#(P)""#
			}], "\n")
		}
		defs: cli.Print & {
			$after: imports
			_exclude: {
				customresourcedefinitions: _
				apiservices:               _
			}
			text: strings.Join([for v, vv in cluster.apiResources for k, kv in vv if _exclude[kv.name] == _|_ {
				"\(kv.name)?: [_]: \(_pkgId[kv.package]).#\(k)"
			}], "\n")
		}
		read: file.Read & {
			filename: FN
			contents: string
		}
		remove: file.RemoveAll & {
			$after: read
			path:   FN
		}
		create: file.Create & {
			$after: remove
			let I = "\t// cue cmd imports\n"
			let D = "\t// cue cmd defs\n"
			filename: FN
			contents: regexp.ReplaceAll(
					"\(D).*\(D)",
					regexp.ReplaceAll("\(I).*\(I)", read.contents, "\(I)\(imports.text)\n\(I)"),
					"\(D)\(defs.text)\n\(D)")
		}
		fmt: exec.Run & {
			$after: create
			cmd:    "cue fmt \(FN)"
		}
	}
	examples: cli.Print & {
		_exclude: events: _
		text: strings.Join([for v, vv in cluster.apiResources for k, kv in vv if _exclude[kv.name] == _|_ {"\(kv.name): exp: _"}], "\n")
	}
	"api-resources": {
		run: exec.Run & {
			cmd:    "kubectl api-resources"
			stdout: string
		}
		mkdir: file.Mkdir & {
			path: ".cluster"
		}
		txt: file.Create & {
			filename: "\(mkdir.path)/api-resources.txt"
			contents: run.stdout
		}
		txtPrint: cli.Print & {
			text: strings.Join([run.cmd, txt.contents], "\n\n")
		}
		J="json": file.Create & {
			_locals: {
				lines:   strings.Split(run.stdout, "\n")
				headers: strings.Fields(lines[0])
				records: [for ln in lines[1:] if ln != "" {
					let FLDS = strings.Fields(ln)
					if len(FLDS) < len(headers) {
						let HDRS = [for h in headers if h != "SHORTNAMES" {h}]
						for i, _ in FLDS {(HDRS[i]): FLDS[i]}
					}
					if len(FLDS) == len(headers) {
						for i, _ in FLDS {(headers[i]): FLDS[i]}
					}
				}]
				gvk: {for r in _locals.records {
					(r.APIVERSION): (r.KIND): {
						name:       r.NAME
						namespaced: r.NAMESPACED
						if r.SHORTNAMES != _|_ {
							shortnames: strings.Split(r.SHORTNAMES, ",")
						}
						let P = strings.Replace(r.APIVERSION, ".k8s.io", "", -1)
						package: *"k8s.io/api/\(P)" | _
						if r.APIVERSION == "v1" {
							package: "k8s.io/api/core/v1"
						}
					}
				}}
			}
			filename: "\(mkdir.path)/api-resources.json"
			contents: json.Indent(json.Marshal(_locals.gvk), "", "  ")
		}
		jsonPrint: cli.Print & {
			$after: txtPrint
			text: strings.Join(["Convert to JSON", J.contents], "\n\n")
		}
	}
}
